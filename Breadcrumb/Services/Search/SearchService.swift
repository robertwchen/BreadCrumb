import CoreGraphics
import Foundation
import UIKit

struct RemoteCandidateHint: Codable, Sendable {
    var candidateID: UUID
    var boundingBox: RectData
    var confidence: Double
    var currentEventType: String?
}

struct RemoteDetection: Codable, Sendable {
    var backendTrackID: String?
    var phrase: String?
    var confidence: Double
    var boundingBox: RectData
    var embeddingDigest: String?
    var sceneSummary: String?
}

struct RemoteFrameRefinementResponse: Codable, Sendable {
    var detections: [RemoteDetection]
    var sceneSummary: String?
    var backend: String
}

enum BackendClientError: LocalizedError {
    case invalidConfiguration
    case invalidImageData
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The backend URL is not configured."
        case .invalidImageData:
            return "The frame could not be encoded for backend refinement."
        case .badResponse:
            return "The backend returned an invalid response."
        }
    }
}

final class BackendPerceptionClient: @unchecked Sendable {
    private let session: URLSession
    private let baseURL: URL?

    init(
        session: URLSession = .shared,
        baseURL: URL? = ProcessInfo.processInfo.environment["BREADCRUMB_BACKEND_URL"].flatMap(URL.init(string:))
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    var isConfigured: Bool {
        baseURL != nil
    }

    func analyzeFrame(
        image: UIImage,
        sessionID: UUID,
        timestamp: Date,
        candidateHints: [RemoteCandidateHint]
    ) async throws -> RemoteFrameRefinementResponse {
        guard let baseURL else {
            throw BackendClientError.invalidConfiguration
        }
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw BackendClientError.invalidImageData
        }

        var request = URLRequest(url: baseURL.appending(path: "/v1/frame/analyze"))
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let payload = RemoteFrameRequestPayload(
            sessionID: sessionID,
            timestamp: timestamp,
            candidateHints: candidateHints
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metadata = try encoder.encode(payload)

        var body = Data()
        body.appendMultipartField(name: "metadata", filename: "metadata.json", mimeType: "application/json", data: metadata, boundary: boundary)
        body.appendMultipartField(name: "image", filename: "frame.jpg", mimeType: "image/jpeg", data: imageData, boundary: boundary)
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw BackendClientError.badResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RemoteFrameRefinementResponse.self, from: data)
    }
}

private struct RemoteFrameRequestPayload: Codable {
    var sessionID: UUID
    var timestamp: Date
    var candidateHints: [RemoteCandidateHint]
}

final class SearchService: @unchecked Sendable {
    func counts(
        trackedObjects: [TrackedObject],
        candidates: [ObjectCandidate],
        sessions: [TrackingSession],
        events: [ObjectObservationEvent],
        states: [LastKnownObjectState],
        interactions: [HandInteractionRecord]
    ) -> BreadcrumbCounts {
        let objectSummaries = objectStatusSummaries(
            trackedObjects: trackedObjects,
            candidates: candidates,
            states: states,
            events: events,
            interactions: interactions
        )

        return BreadcrumbCounts(
            trackedObjectCount: trackedObjects.count,
            inboxCandidateCount: candidates.filter { $0.candidateStatus == .inbox }.count,
            promotedCandidateCount: candidates.filter { $0.candidateStatus == .promoted }.count,
            sessionCount: sessions.count,
            eventCount: events.count,
            possibleMissingCount: objectSummaries.filter(\.isPossiblyLost).count,
            recentlyHandledCount: objectSummaries.filter(\.isRecentlyHandled).count
        )
    }

    func sessionSnapshots(from sessions: [TrackingSession]) -> [SessionSnapshot] {
        sessions
            .map {
                SessionSnapshot(
                    id: $0.id,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    status: $0.status,
                    sessionLabel: $0.sessionLabel,
                    analyzedFrameCount: $0.analyzedFrameCount,
                    localCandidateCount: $0.localCandidateCount,
                    remoteRefinementEnabled: $0.remoteRefinementEnabled,
                    backendStatusNote: $0.backendStatusNote
                )
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func eventSnapshots(from events: [ObjectObservationEvent]) -> [EventSnapshot] {
        events
            .map {
                EventSnapshot(
                    id: $0.id,
                    sessionID: $0.sessionID,
                    candidateID: $0.candidateID,
                    trackedObjectID: $0.trackedObjectID,
                    timestamp: $0.timestamp,
                    eventType: $0.eventType,
                    confidence: $0.confidence,
                    boundingBox: $0.boundingBox,
                    contextLabel: $0.contextLabel,
                    sceneLabel: $0.sceneLabel,
                    likelyLocation: $0.likelyLocation,
                    evidencePath: $0.evidencePath,
                    note: $0.note,
                    inferenceSource: $0.inferenceSource
                )
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func interactionSnapshots(from interactions: [HandInteractionRecord]) -> [HandInteractionSnapshot] {
        interactions
            .map {
                HandInteractionSnapshot(
                    id: $0.id,
                    candidateID: $0.candidateID,
                    trackedObjectID: $0.trackedObjectID,
                    sessionID: $0.sessionID,
                    pickupTimestamp: $0.pickupTimestamp,
                    putDownTimestamp: $0.putDownTimestamp,
                    contextSummary: $0.contextSummary
                )
            }
            .sorted { $0.pickupTimestamp > $1.pickupTimestamp }
    }

    func candidateSummaries(
        candidates: [ObjectCandidate],
        trackedObjects: [TrackedObject],
        states: [LastKnownObjectState],
        events: [ObjectObservationEvent]
    ) -> [CandidateSummary] {
        let promotedByID = Dictionary(uniqueKeysWithValues: trackedObjects.map { ($0.id, $0) })
        let stateByCandidateID = Dictionary(uniqueKeysWithValues: states.map { ($0.candidateID, stateSnapshot(from: $0)) })
        let eventsByCandidateID = Dictionary(grouping: eventSnapshots(from: events), by: \.candidateID)

        return candidates
            .filter { $0.candidateStatus != .dismissed }
            .map { candidate in
                let promotedObject = candidate.promotedTrackedObjectID.flatMap { promotedByID[$0] }
                let title = promotedObject?.displayName
                    ?? candidate.latestLabelHint
                    ?? "Detected object \(candidate.id.uuidString.prefix(4))"
                let subtitle = promotedObject == nil
                    ? "Auto-discovered while observing"
                    : "Confirmed from automatic discovery"

                return CandidateSummary(
                    id: candidate.id,
                    promotedTrackedObjectID: candidate.promotedTrackedObjectID,
                    title: title,
                    subtitle: subtitle,
                    candidateStatus: candidate.candidateStatus,
                    observationCount: candidate.observationCount,
                    clusterConfidence: candidate.clusterConfidence,
                    latestEvidencePath: candidate.latestEvidenceThumbnailPath,
                    lastState: stateByCandidateID[candidate.id],
                    recentEvents: Array((eventsByCandidateID[candidate.id] ?? []).prefix(6)),
                    isPinned: candidate.isPinned
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.lastSeenAt, rhs.lastSeenAt) {
                case let (lhsDate?, rhsDate?):
                    return lhsDate > rhsDate
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.observationCount > rhs.observationCount
                }
            }
    }

    func objectStatusSummaries(
        trackedObjects: [TrackedObject],
        candidates: [ObjectCandidate],
        states: [LastKnownObjectState],
        events: [ObjectObservationEvent],
        interactions: [HandInteractionRecord]
    ) -> [ObjectStatusSummary] {
        let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let stateByCandidateID = Dictionary(uniqueKeysWithValues: states.map { ($0.candidateID, stateSnapshot(from: $0)) })
        let eventsByCandidateID = Dictionary(grouping: eventSnapshots(from: events), by: \.candidateID)
        let interactionsByCandidateID = Dictionary(grouping: interactionSnapshots(from: interactions), by: \.candidateID)

        return trackedObjects.map { object in
            let candidate = object.candidateOriginID.flatMap { candidateByID[$0] }
            let candidateID = candidate?.id

            return ObjectStatusSummary(
                id: object.id,
                objectID: object.id,
                candidateID: candidateID,
                displayName: object.displayName,
                userNotes: object.userNotes,
                primaryReferenceImagePath: object.primaryReferenceImagePath ?? candidate?.latestEvidenceThumbnailPath,
                latestEvidencePath: candidate?.latestEvidenceThumbnailPath,
                lastState: candidateID.flatMap { stateByCandidateID[$0] },
                recentEvents: Array(candidateID.flatMap { eventsByCandidateID[$0] }?.prefix(8) ?? []),
                interactions: candidateID.flatMap { interactionsByCandidateID[$0] } ?? [],
                isPinned: object.isPinned
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.lastHandledAt, rhs.lastHandledAt) {
            case let (lhsDate?, rhsDate?):
                return lhsDate > rhsDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }

            switch (lhs.lastState?.lastSeenAt, rhs.lastState?.lastSeenAt) {
            case let (lhsDate?, rhsDate?):
                return lhsDate > rhsDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    func candidateHistory(
        candidateID: UUID,
        candidates: [ObjectCandidate],
        trackedObjects: [TrackedObject],
        states: [LastKnownObjectState],
        events: [ObjectObservationEvent]
    ) -> CandidateHistorySummary? {
        guard let summary = candidateSummaries(
            candidates: candidates,
            trackedObjects: trackedObjects,
            states: states,
            events: events
        ).first(where: { $0.id == candidateID }) else {
            return nil
        }

        let recentEvents = eventSnapshots(from: events)
            .filter { $0.candidateID == candidateID }
            .sorted { $0.timestamp > $1.timestamp }

        return CandidateHistorySummary(
            candidateSummary: summary,
            recentEvents: recentEvents
        )
    }

    func objectHistory(
        objectID: UUID,
        trackedObjects: [TrackedObject],
        candidates: [ObjectCandidate],
        states: [LastKnownObjectState],
        events: [ObjectObservationEvent],
        interactions: [HandInteractionRecord]
    ) -> ObjectHistorySummary? {
        let summaries = objectStatusSummaries(
            trackedObjects: trackedObjects,
            candidates: candidates,
            states: states,
            events: events,
            interactions: interactions
        )

        guard let summary = summaries.first(where: { $0.objectID == objectID }) else { return nil }

        return ObjectHistorySummary(
            objectSummary: summary,
            recentEvents: summary.recentEvents,
            interactions: summary.interactions
        )
    }

    func liveStatuses(
        activeSessionID: UUID,
        objectSummaries: [ObjectStatusSummary],
        candidateSummaries: [CandidateSummary]
    ) -> [LiveCandidateStatus] {
        let objectStatuses = objectSummaries.compactMap { summary -> LiveCandidateStatus? in
            guard let lastState = summary.lastState, lastState.lastSessionID == activeSessionID else { return nil }
            guard Date().timeIntervalSince(lastState.lastSeenAt) < 4 else { return nil }

            return LiveCandidateStatus(
                id: summary.candidateID ?? summary.id,
                title: summary.displayName,
                isPromoted: true,
                eventTitle: lastState.lastEventType.title,
                confidence: lastState.confidence,
                contextSummary: lastState.lastContextSummary,
                likelyLocation: lastState.likelyLocation,
                boundingBox: lastState.lastBoundingBox,
                uncertaintySummary: uncertaintySummary(for: lastState.lastEventType, confidence: lastState.confidence, isPromoted: true)
            )
        }

        let objectCandidateIDs = Set(objectStatuses.map(\.id))
        let candidateStatuses = candidateSummaries.compactMap { summary -> LiveCandidateStatus? in
            guard summary.candidateStatus == .inbox else { return nil }
            guard let lastState = summary.lastState, lastState.lastSessionID == activeSessionID else { return nil }
            guard Date().timeIntervalSince(lastState.lastSeenAt) < 4 else { return nil }
            guard !objectCandidateIDs.contains(summary.id) else { return nil }

            return LiveCandidateStatus(
                id: summary.id,
                title: summary.title,
                isPromoted: false,
                eventTitle: lastState.lastEventType.title,
                confidence: lastState.confidence,
                contextSummary: lastState.lastContextSummary,
                likelyLocation: lastState.likelyLocation,
                boundingBox: lastState.lastBoundingBox,
                uncertaintySummary: uncertaintySummary(for: lastState.lastEventType, confidence: lastState.confidence, isPromoted: false)
            )
        }

        return (objectStatuses + candidateStatuses)
            .sorted { $0.confidence > $1.confidence }
    }

    private func stateSnapshot(from state: LastKnownObjectState) -> LastKnownStateSnapshot {
        LastKnownStateSnapshot(
            candidateID: state.candidateID,
            trackedObjectID: state.trackedObjectID,
            lastEventType: state.lastEventType,
            lastSeenAt: state.lastSeenAt,
            lastContextSummary: state.lastContextSummary,
            likelyLocation: state.likelyLocation,
            isPossiblyLost: state.isPossiblyLost,
            confidence: state.confidence,
            lastBoundingBox: state.lastBoundingBox,
            lastThumbnailPath: state.lastThumbnailPath,
            lastSessionID: state.lastSessionID,
            lastPickupAt: state.lastPickupAt,
            lastPutDownAt: state.lastPutDownAt
        )
    }

    private func uncertaintySummary(
        for eventType: ObservationEventType,
        confidence: Double,
        isPromoted: Bool
    ) -> String {
        if confidence < 0.62 {
            return isPromoted
                ? "Tracking is tentative right now."
                : "Auto identity is still tentative."
        }

        switch eventType {
        case .pickedUp, .inHand, .lostFromViewLikelyCarried:
            return "Interaction is inferred from tracked motion and hand evidence."
        case .reidentified:
            return "Identity was recovered after a short loss from view."
        case .restingOnSurface, .putDown:
            return "State is supported by stable tracking away from the hand."
        case .seen:
            return isPromoted
                ? "Seen again, but the interaction state is still building."
                : "Auto-detected candidate is still building identity confidence."
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendMultipartField(
        name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }
}
