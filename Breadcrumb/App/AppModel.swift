import CoreMedia
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var hasLoaded = false
    @Published private(set) var counts = BreadcrumbCounts(
        trackedObjectCount: 0,
        inboxCandidateCount: 0,
        promotedCandidateCount: 0,
        sessionCount: 0,
        eventCount: 0,
        possibleMissingCount: 0,
        recentlyHandledCount: 0
    )
    @Published private(set) var trackedObjects: [TrackedObject] = []
    @Published private(set) var candidateSummaries: [CandidateSummary] = []
    @Published private(set) var objectStatusSummaries: [ObjectStatusSummary] = []
    @Published private(set) var sessions: [SessionSnapshot] = []
    @Published private(set) var recentEvents: [EventSnapshot] = []
    @Published private(set) var activeSession: SessionSnapshot?
    @Published private(set) var activeRecognitions: [LiveCandidateStatus] = []
    @Published private(set) var recentSessionEvents: [EventSnapshot] = []
    @Published private(set) var isAnalyzingFrame = false
    @Published private(set) var backendConfigured = false
    @Published private(set) var backendStatusMessage = "On-device only"

    private let container: ModelContainer
    private let context: ModelContext
    private let store: LibraryStore
    private let searchService: SearchService
    private let analyzer: ObjectTrackingAnalyzer
    private let backendClient: BackendPerceptionClient

    private var candidates: [ObjectCandidate] = []
    private var observations: [ObservationRecord] = []
    private var states: [LastKnownObjectState] = []
    private var eventEntities: [ObjectObservationEvent] = []
    private var interactionEntities: [HandInteractionRecord] = []
    private var sessionEntities: [TrackingSession] = []
    private var pendingFrame: CameraVideoFrame?
    private var lastProcessedPresentationTimestamp: CMTime = .invalid

    init(
        container: ModelContainer,
        store: LibraryStore = LibraryStore(),
        searchService: SearchService = SearchService(),
        analyzer: ObjectTrackingAnalyzer = ObjectTrackingAnalyzer(),
        backendClient: BackendPerceptionClient = BackendPerceptionClient()
    ) {
        self.container = container
        self.context = ModelContext(container)
        self.store = store
        self.searchService = searchService
        self.analyzer = analyzer
        self.backendClient = backendClient
    }

    var inboxCandidates: [CandidateSummary] {
        candidateSummaries.filter { $0.candidateStatus == .inbox }
    }

    var promotedCandidates: [CandidateSummary] {
        candidateSummaries.filter(\.isPromoted)
    }

    var recentlyHandledObjects: [ObjectStatusSummary] {
        objectStatusSummaries.filter(\.isRecentlyHandled)
    }

    var possiblyLostObjects: [ObjectStatusSummary] {
        objectStatusSummaries.filter(\.isPossiblyLost)
    }

    var lastCompletedSession: SessionSnapshot? {
        sessions.first(where: { $0.status == .completed })
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        backendConfigured = backendClient.isConfigured
        backendStatusMessage = backendConfigured
            ? "Local Apple Vision pipeline active. Hosted refinement is configured separately."
            : "Local Apple Vision pipeline active"

        do {
            try closeDanglingSessions()
            refreshState()
            hasLoaded = true
        } catch {
            print("Breadcrumb load failed: \(error.localizedDescription)")
            hasLoaded = true
        }
    }

    func image(for relativePath: String) -> UIImage? {
        store.loadImage(relativePath: relativePath)
    }

    func createTrackedObject(name: String, notes: String, referenceImages: [UIImage]) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let referencePaths = try referenceImages.map { image in
            try store.saveJPEG(image, id: UUID(), folder: .references)
        }

        if referencePaths.isEmpty {
            let object = TrackedObject(
                displayName: cleanName,
                userNotes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                isPinned: true
            )
            context.insert(object)
            try context.save()
            refreshState()
            return
        }

        let candidate = ObjectCandidate(
            lastSeenAt: Date(),
            observationCount: referencePaths.count,
            candidateStatus: .promoted,
            clusterConfidence: 1.0,
            latestContextSummary: "Added manually with optional reference photos",
            latestEvidenceThumbnailPath: referencePaths.first,
            latestSceneLabel: "manual object note",
            latestLocationSummary: "No observed location yet",
            manualReferenceImagePaths: encodePathList(referencePaths),
            lastEventConfidence: 1.0,
            isPinned: true
        )

        let object = TrackedObject(
            displayName: cleanName,
            userNotes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            candidateOriginID: candidate.id,
            manualReferenceImagePaths: encodePathList(referencePaths),
            isPinned: true
        )

        candidate.promotedTrackedObjectID = object.id
        context.insert(candidate)
        context.insert(object)
        try context.save()
        refreshState()
    }

    func startSession(label: String) async throws {
        guard activeSession == nil else { return }

        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = TrackingSession(
            startedAt: Date(),
            status: .recording,
            sessionLabel: cleanLabel.isEmpty ? "Recording session" : cleanLabel,
            remoteRefinementEnabled: false,
            backendStatusNote: backendStatusMessage
        )

        context.insert(session)
        try context.save()
        refreshState()
        recentSessionEvents = []
        activeRecognitions = []
        pendingFrame = nil
        lastProcessedPresentationTimestamp = .invalid
        await analyzer.prepare(candidates: candidateReferenceSeeds(), imageLoader: store.loadImage(relativePath:))
    }

    func stopSession() async throws {
        guard let activeSession else { return }
        guard let session = sessionEntities.first(where: { $0.id == activeSession.id }) else { return }

        session.status = .completed
        session.endedAt = Date()
        try context.save()
        pendingFrame = nil
        lastProcessedPresentationTimestamp = .invalid
        isAnalyzingFrame = false
        await analyzer.reset()
        refreshState()
    }

    func processRecordingFrame(_ frame: CameraVideoFrame) {
        guard let activeSession else { return }

        if lastProcessedPresentationTimestamp.isValid,
           CMTimeCompare(frame.presentationTimestamp, lastProcessedPresentationTimestamp) <= 0 {
            return
        }

        if isAnalyzingFrame {
            if let pendingFrame,
               CMTimeCompare(frame.presentationTimestamp, pendingFrame.presentationTimestamp) <= 0 {
                return
            }
            pendingFrame = frame
            return
        }

        beginFrameAnalysis(frame, sessionID: activeSession.id)
    }

    private func beginFrameAnalysis(_ frame: CameraVideoFrame, sessionID: UUID) {
        isAnalyzingFrame = true
        Task {
            let analysis = await analyzer.analyzeFrame(frame)

            await MainActor.run {
                defer {
                    self.lastProcessedPresentationTimestamp = frame.presentationTimestamp
                    self.finishQueuedFrameAnalysis(for: sessionID)
                }

                do {
                    try self.applyFrameAnalysis(analysis, sessionID: sessionID, timestamp: frame.timestamp)
                } catch {
                    self.backendStatusMessage = "On-device analysis failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func finishQueuedFrameAnalysis(for sessionID: UUID) {
        guard activeSession?.id == sessionID else {
            pendingFrame = nil
            isAnalyzingFrame = false
            return
        }

        guard let nextFrame = pendingFrame else {
            isAnalyzingFrame = false
            return
        }

        pendingFrame = nil
        beginFrameAnalysis(nextFrame, sessionID: sessionID)
    }

    func promoteCandidate(candidateID: UUID, displayName: String, notes: String) throws {
        guard let candidate = candidates.first(where: { $0.id == candidateID }) else { return }
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        if let existingID = candidate.promotedTrackedObjectID,
           let existingObject = trackedObjects.first(where: { $0.id == existingID }) {
            existingObject.displayName = cleanName
            existingObject.userNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let object = TrackedObject(
                displayName: cleanName,
                userNotes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                candidateOriginID: candidate.id,
                manualReferenceImagePaths: encodePathList(candidate.referenceImagePaths),
                isPinned: true
            )
            context.insert(object)
            candidate.promotedTrackedObjectID = object.id
        }

        candidate.candidateStatus = .promoted
        candidate.isPinned = true
        try context.save()
        refreshState()
    }

    func dismissCandidate(candidateID: UUID) throws {
        guard let candidate = candidates.first(where: { $0.id == candidateID }) else { return }
        candidate.candidateStatus = .dismissed
        try context.save()
        refreshState()
    }

    func addReferenceImage(_ image: UIImage, to objectID: UUID) throws {
        guard let object = trackedObjects.first(where: { $0.id == objectID }) else { return }
        let referencePath = try store.saveJPEG(image, id: UUID(), folder: .references)
        object.appendReferenceImagePath(referencePath)

        if let candidateID = object.candidateOriginID,
           let candidate = candidates.first(where: { $0.id == candidateID }) {
            candidate.appendReferenceImagePath(referencePath)
        }

        try context.save()
        refreshState()
    }

    func togglePinnedForObject(_ objectID: UUID) throws {
        guard let object = trackedObjects.first(where: { $0.id == objectID }) else { return }
        object.isPinned.toggle()
        try context.save()
        refreshState()
    }

    func togglePinnedForCandidate(_ candidateID: UUID) throws {
        guard let candidate = candidates.first(where: { $0.id == candidateID }) else { return }
        candidate.isPinned.toggle()
        try context.save()
        refreshState()
    }

    func clearLibrary() throws {
        for object in trackedObjects {
            context.delete(object)
        }
        for candidate in candidates {
            context.delete(candidate)
        }
        for observation in observations {
            context.delete(observation)
        }
        for state in states {
            context.delete(state)
        }
        for event in eventEntities {
            context.delete(event)
        }
        for interaction in interactionEntities {
            context.delete(interaction)
        }
        for session in sessionEntities {
            context.delete(session)
        }

        try context.save()
        try store.resetAllData()
        pendingFrame = nil
        lastProcessedPresentationTimestamp = .invalid
        isAnalyzingFrame = false
        Task {
            await analyzer.reset()
        }
        refreshState()
    }

    func candidateHistory(for candidateID: UUID) -> CandidateHistorySummary? {
        searchService.candidateHistory(
            candidateID: candidateID,
            candidates: candidates,
            trackedObjects: trackedObjects,
            states: states,
            events: eventEntities
        )
    }

    func history(for objectID: UUID) -> ObjectHistorySummary? {
        searchService.objectHistory(
            objectID: objectID,
            trackedObjects: trackedObjects,
            candidates: candidates,
            states: states,
            events: eventEntities,
            interactions: interactionEntities
        )
    }

    func candidateSummary(for candidateID: UUID) -> CandidateSummary? {
        candidateSummaries.first(where: { $0.id == candidateID })
    }

    func objectSummary(for objectID: UUID) -> ObjectStatusSummary? {
        objectStatusSummaries.first(where: { $0.objectID == objectID })
    }

    func sessionEvents(for sessionID: UUID) -> [EventSnapshot] {
        recentEvents.filter { $0.sessionID == sessionID }
    }

    func displayTitle(for candidateID: UUID, objectID: UUID?) -> String {
        if let objectID, let summary = objectSummary(for: objectID) {
            return summary.displayName
        }

        if let candidate = candidateSummary(for: candidateID) {
            return candidate.title
        }

        return "Unknown candidate"
    }

    private func candidateReferenceSeeds() -> [(id: UUID, referencePaths: [String])] {
        candidates.map { candidate in
            var paths = candidate.allReferenceImagePaths

            if let trackedObjectID = candidate.promotedTrackedObjectID,
               let trackedObject = trackedObjects.first(where: { $0.id == trackedObjectID }) {
                paths.append(contentsOf: trackedObject.referenceImagePaths)
            }

            let recentObservationEvidence = observations
                .filter { $0.candidateID == candidate.id }
                .sorted { $0.timestamp > $1.timestamp }
                .compactMap(\.evidencePath)
                .prefix(4)
            let recentEventEvidence = eventEntities
                .filter { $0.candidateID == candidate.id }
                .sorted { $0.timestamp > $1.timestamp }
                .compactMap(\.evidencePath)
                .prefix(2)

            paths.append(contentsOf: recentObservationEvidence)
            paths.append(contentsOf: recentEventEvidence)

            return (candidate.id, Array(Set(paths)))
        }
    }

    private func applyFrameAnalysis(
        _ analysis: FrameAnalysisResult,
        sessionID: UUID,
        timestamp: Date
    ) throws {
        guard let session = sessionEntities.first(where: { $0.id == sessionID }) else { return }
        session.analyzedFrameCount += 1

        for sighting in analysis.sightings {
            let candidate = try upsertCandidate(from: sighting)
            let trackedObjectID = candidate.promotedTrackedObjectID
            var latestEvidencePath = candidate.latestEvidenceThumbnailPath

            if shouldPersistObservation(for: sighting, sessionID: sessionID) {
                let evidencePath = try store.saveJPEG(sighting.thumbnail, id: UUID(), folder: .candidateEvidence, compression: 0.58)
                candidate.latestEvidenceThumbnailPath = evidencePath
                candidate.observationCount += 1
                latestEvidencePath = evidencePath

                let observation = ObservationRecord(
                    sessionID: sessionID,
                    candidateID: candidate.id,
                    trackedObjectID: trackedObjectID,
                    timestamp: timestamp,
                    boundingBox: RectData(sighting.boundingBox),
                    confidence: sighting.confidence,
                    source: .localVision,
                    sceneLabel: sighting.sceneLabel,
                    contextLabel: sighting.contextLabel,
                    likelyLocation: sighting.likelyLocation,
                    evidencePath: evidencePath,
                    embeddingDigest: candidate.embeddingDigest,
                    remoteTrackID: candidate.latestRemoteTrackID,
                    handConfidence: sighting.handConfidence,
                    motionScore: sighting.motionScore,
                    labelHint: sighting.labelHint
                )
                context.insert(observation)
            }

            refreshLastSeenState(
                from: sighting,
                candidate: candidate,
                sessionID: sessionID,
                thumbnailPath: latestEvidencePath
            )
        }

        for event in analysis.events where shouldPersistEvent(event, sessionID: sessionID) {
            guard let candidate = candidates.first(where: { $0.id == event.candidateID }) else { continue }
            let evidencePath = try event.thumbnail.map {
                try store.saveJPEG($0, id: UUID(), folder: .eventEvidence, compression: 0.56)
            }

            let trackedObjectID = candidate.promotedTrackedObjectID
            let eventEntity = ObjectObservationEvent(
                sessionID: sessionID,
                candidateID: candidate.id,
                trackedObjectID: trackedObjectID,
                timestamp: event.timestamp,
                eventType: event.eventType,
                confidence: event.confidence,
                boundingBox: event.boundingBox.map(RectData.init),
                contextLabel: event.contextLabel,
                sceneLabel: event.sceneLabel,
                likelyLocation: event.likelyLocation,
                evidencePath: evidencePath,
                note: event.note
            )
            context.insert(eventEntity)
            updateState(for: eventEntity, candidate: candidate)
            updateHandInteractions(for: eventEntity)
        }

        session.localCandidateCount = Set(
            observations.filter { $0.sessionID == sessionID }.map(\.candidateID)
                + analysis.sightings.map(\.candidateID)
        ).count

        try context.save()
        refreshState()
    }

    private func upsertCandidate(from sighting: AnalyzerSighting) throws -> ObjectCandidate {
        if let existing = candidates.first(where: { $0.id == sighting.candidateID }) {
            existing.lastSeenAt = sighting.timestamp
            existing.clusterConfidence = min(0.99, max(existing.clusterConfidence * 0.92, sighting.confidence))
            existing.latestBoundingBox = RectData(sighting.boundingBox)
            existing.latestContextSummary = sighting.contextLabel
            existing.latestLocationSummary = sighting.likelyLocation
            existing.latestSceneLabel = sighting.sceneLabel
            existing.latestLabelHint = sighting.labelHint ?? existing.latestLabelHint
            return existing
        }

        let candidate = ObjectCandidate(
            id: sighting.candidateID,
            lastSeenAt: sighting.timestamp,
            observationCount: 0,
            candidateStatus: .inbox,
            clusterConfidence: sighting.confidence,
            latestBoundingBox: RectData(sighting.boundingBox),
            latestContextSummary: sighting.contextLabel,
            latestSceneLabel: sighting.sceneLabel,
            latestLocationSummary: sighting.likelyLocation,
            latestLabelHint: sighting.labelHint,
            lastEventTypeRaw: ObservationEventType.seen.rawValue,
            lastEventConfidence: sighting.confidence
        )
        context.insert(candidate)
        return candidate
    }

    private func shouldPersistObservation(for sighting: AnalyzerSighting, sessionID: UUID) -> Bool {
        guard let latest = observations.last(where: { $0.sessionID == sessionID && $0.candidateID == sighting.candidateID }) else {
            return true
        }

        if sighting.wasNewCandidate {
            return true
        }

        if sighting.timestamp.timeIntervalSince(latest.timestamp) >= 1.2 {
            return true
        }

        guard let latestBox = latest.boundingBox?.cgRect else {
            return true
        }

        return latestBox.intersection(sighting.boundingBox).area / max(latestBox.area, sighting.boundingBox.area) < 0.72
    }

    private func shouldPersistEvent(_ proposal: AnalyzerEventProposal, sessionID: UUID) -> Bool {
        let candidateEvents = eventEntities
            .filter { $0.sessionID == sessionID && $0.candidateID == proposal.candidateID }
            .sorted { $0.timestamp > $1.timestamp }

        if proposal.eventType == .pickedUp,
           interactionEntities.contains(where: { $0.candidateID == proposal.candidateID && $0.putDownTimestamp == nil }) {
            return false
        }

        if proposal.eventType == .pickedUp,
           let latestHandlingEvent = candidateEvents.first(where: {
               [.pickedUp, .inHand, .lostFromViewLikelyCarried, .reidentified].contains($0.eventType)
           }) {
            let hasInterveningClosure = candidateEvents.contains(where: {
                $0.timestamp > latestHandlingEvent.timestamp
                    && [.putDown, .restingOnSurface].contains($0.eventType)
            })

            if !hasInterveningClosure, proposal.timestamp.timeIntervalSince(latestHandlingEvent.timestamp) < 8 {
                return false
            }
        }

        guard let latestEvent = candidateEvents.first else {
            return true
        }

        if latestEvent.eventType == proposal.eventType {
            let dedupeWindow: TimeInterval
            switch proposal.eventType {
            case .inHand:
                dedupeWindow = 1.8
            case .restingOnSurface:
                dedupeWindow = 3.2
            default:
                dedupeWindow = 2.8
            }

            if proposal.timestamp.timeIntervalSince(latestEvent.timestamp) < dedupeWindow {
                return false
            }
        }

        if latestEvent.eventType == proposal.eventType,
           latestEvent.contextLabel == proposal.contextLabel,
           proposal.timestamp.timeIntervalSince(latestEvent.timestamp) < 6.0 {
            return false
        }

        return true
    }

    private func updateState(for event: ObjectObservationEvent, candidate: ObjectCandidate) {
        let state = states.first(where: { $0.candidateID == candidate.id }) ?? {
            let newState = LastKnownObjectState(
                candidateID: candidate.id,
                trackedObjectID: candidate.promotedTrackedObjectID,
                lastEventType: event.eventType,
                lastSeenAt: event.timestamp,
                lastContextSummary: event.contextLabel ?? "Context not stable yet",
                likelyLocation: event.likelyLocation ?? "Location not stable yet",
                isPossiblyLost: event.eventType.impliesMissingState,
                confidence: event.confidence,
                lastBoundingBox: event.boundingBox,
                lastThumbnailPath: event.evidencePath,
                lastSessionID: event.sessionID
            )
            context.insert(newState)
            states.append(newState)
            return newState
        }()

        state.trackedObjectID = candidate.promotedTrackedObjectID
        state.lastEventType = event.eventType
        state.lastSeenAt = event.timestamp
        state.lastContextSummary = event.contextLabel ?? state.lastContextSummary
        state.likelyLocation = event.likelyLocation ?? state.likelyLocation
        state.isPossiblyLost = event.eventType.impliesMissingState
        state.confidence = event.confidence
        state.lastBoundingBox = event.boundingBox ?? state.lastBoundingBox
        state.lastThumbnailPath = event.evidencePath ?? state.lastThumbnailPath
        state.lastSessionID = event.sessionID

        if event.eventType == .pickedUp {
            state.lastPickupAt = event.timestamp
            state.isPossiblyLost = false
        } else if event.eventType == .putDown {
            state.lastPutDownAt = event.timestamp
            state.isPossiblyLost = false
        } else if event.eventType == .reidentified || event.eventType == .restingOnSurface || event.eventType == .seen {
            state.isPossiblyLost = false
        }

        candidate.lastEventType = event.eventType
        candidate.lastEventConfidence = event.confidence
        candidate.lastSeenAt = event.timestamp
        candidate.latestContextSummary = event.contextLabel ?? candidate.latestContextSummary
        candidate.latestLocationSummary = event.likelyLocation ?? candidate.latestLocationSummary
        candidate.latestSceneLabel = event.sceneLabel ?? candidate.latestSceneLabel
        candidate.latestBoundingBox = event.boundingBox ?? candidate.latestBoundingBox
        candidate.latestEvidenceThumbnailPath = event.evidencePath ?? candidate.latestEvidenceThumbnailPath
    }

    private func refreshLastSeenState(
        from sighting: AnalyzerSighting,
        candidate: ObjectCandidate,
        sessionID: UUID,
        thumbnailPath: String?
    ) {
        let state = states.first(where: { $0.candidateID == candidate.id }) ?? {
            let newState = LastKnownObjectState(
                candidateID: candidate.id,
                trackedObjectID: candidate.promotedTrackedObjectID,
                lastEventType: candidate.lastEventType ?? .seen,
                lastSeenAt: sighting.timestamp,
                lastContextSummary: sighting.contextLabel,
                likelyLocation: sighting.likelyLocation,
                isPossiblyLost: false,
                confidence: sighting.confidence,
                lastBoundingBox: RectData(sighting.boundingBox),
                lastThumbnailPath: thumbnailPath,
                lastSessionID: sessionID
            )
            context.insert(newState)
            states.append(newState)
            return newState
        }()

        state.trackedObjectID = candidate.promotedTrackedObjectID
        state.lastSeenAt = sighting.timestamp
        state.lastContextSummary = sighting.contextLabel
        state.likelyLocation = sighting.likelyLocation
        state.confidence = sighting.confidence
        state.lastBoundingBox = RectData(sighting.boundingBox)
        state.lastThumbnailPath = thumbnailPath ?? state.lastThumbnailPath
        state.lastSessionID = sessionID
        state.isPossiblyLost = false
    }

    private func updateHandInteractions(for event: ObjectObservationEvent) {
        switch event.eventType {
        case .pickedUp:
            guard interactionEntities.last(where: { $0.candidateID == event.candidateID && $0.putDownTimestamp == nil }) == nil else {
                return
            }
            let interaction = HandInteractionRecord(
                candidateID: event.candidateID,
                trackedObjectID: event.trackedObjectID,
                sessionID: event.sessionID,
                pickupTimestamp: event.timestamp,
                contextSummary: event.contextLabel ?? "Context not stable yet"
            )
            context.insert(interaction)
        case .putDown:
            guard let interaction = interactionEntities.last(where: { $0.candidateID == event.candidateID && $0.putDownTimestamp == nil }) else {
                return
            }
            interaction.putDownTimestamp = event.timestamp
            interaction.contextSummary = event.contextLabel ?? interaction.contextSummary
        case .inHand, .lostFromViewLikelyCarried, .reidentified:
            guard let interaction = interactionEntities.last(where: { $0.candidateID == event.candidateID && $0.putDownTimestamp == nil }) else {
                return
            }
            interaction.contextSummary = event.contextLabel ?? interaction.contextSummary
        case .seen, .restingOnSurface:
            break
        }
    }

    private func closeDanglingSessions() throws {
        let descriptor = FetchDescriptor<TrackingSession>()
        let sessions = try context.fetch(descriptor)
        let now = Date()
        var mutated = false

        for session in sessions where session.status == .recording {
            session.status = .completed
            session.endedAt = session.endedAt ?? now
            mutated = true
        }

        if mutated {
            try context.save()
        }
    }

    private func refreshState() {
        do {
            trackedObjects = try context.fetch(FetchDescriptor<TrackedObject>())
            candidates = try context.fetch(FetchDescriptor<ObjectCandidate>())
            observations = try context.fetch(FetchDescriptor<ObservationRecord>())
            states = try context.fetch(FetchDescriptor<LastKnownObjectState>())
            eventEntities = try context.fetch(FetchDescriptor<ObjectObservationEvent>())
            interactionEntities = try context.fetch(FetchDescriptor<HandInteractionRecord>())
            sessionEntities = try context.fetch(FetchDescriptor<TrackingSession>())
        } catch {
            print("Breadcrumb refresh failed: \(error.localizedDescription)")
        }

        trackedObjects.sort { $0.createdAt > $1.createdAt }
        candidates.sort { $0.lastSeenAt > $1.lastSeenAt }
        eventEntities.sort { $0.timestamp > $1.timestamp }
        interactionEntities.sort { $0.pickupTimestamp > $1.pickupTimestamp }
        sessionEntities.sort { $0.startedAt > $1.startedAt }

        counts = searchService.counts(
            trackedObjects: trackedObjects,
            candidates: candidates,
            sessions: sessionEntities,
            events: eventEntities,
            states: states,
            interactions: interactionEntities
        )
        candidateSummaries = searchService.candidateSummaries(
            candidates: candidates,
            trackedObjects: trackedObjects,
            states: states,
            events: eventEntities
        )
        objectStatusSummaries = searchService.objectStatusSummaries(
            trackedObjects: trackedObjects,
            candidates: candidates,
            states: states,
            events: eventEntities,
            interactions: interactionEntities
        )
        sessions = searchService.sessionSnapshots(from: sessionEntities)
        recentEvents = searchService.eventSnapshots(from: eventEntities)
        activeSession = sessions.first(where: { $0.status == .recording })
        activeRecognitions = activeSession.map {
            searchService.liveStatuses(
                activeSessionID: $0.id,
                objectSummaries: objectStatusSummaries,
                candidateSummaries: candidateSummaries
            )
        } ?? []
        recentSessionEvents = activeSession.map { sessionEvents(for: $0.id) } ?? []
    }
}

private extension CGRect {
    var area: CGFloat {
        width * height
    }

    func iou(with other: CGRect) -> Double {
        let intersectionArea = intersection(other).area
        guard intersectionArea > 0 else { return 0 }
        return Double(intersectionArea / (area + other.area - intersectionArea))
    }
}
