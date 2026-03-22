import CoreGraphics
import CoreMedia
import UIKit
import Vision

struct AnalyzerSighting {
    var candidateID: UUID
    var timestamp: Date
    var confidence: Double
    var boundingBox: CGRect
    var contextLabel: String
    var likelyLocation: String
    var sceneLabel: String
    var labelHint: String?
    var thumbnail: UIImage
    var handConfidence: Double
    var motionScore: Double
    var wasNewCandidate: Bool
}

struct AnalyzerEventProposal {
    var candidateID: UUID
    var timestamp: Date
    var eventType: ObservationEventType
    var confidence: Double
    var boundingBox: CGRect?
    var contextLabel: String
    var likelyLocation: String
    var sceneLabel: String
    var note: String
    var thumbnail: UIImage?
}

struct FrameAnalysisResult {
    var sightings: [AnalyzerSighting]
    var events: [AnalyzerEventProposal]
}

private struct HandObservation {
    var bounds: CGRect
    var center: CGPoint
    var allPoints: [CGPoint]
    var fingertips: [CGPoint]
}

private struct HandMetrics {
    var confidence: Double
    var pointScore: Double
    var overlapScore: Double
    var distanceScore: Double
}

private struct CandidateTrackState {
    enum Phase {
        case unknown
        case resting
        case inHand
        case missing
    }

    var phase: Phase = .unknown
    var activeObservation: VNDetectedObjectObservation?
    var visibleStreak = 0
    var missingStreak = 0
    var missingDuration: TimeInterval = 0
    var handContactDuration: TimeInterval = 0
    var groundedDuration: TimeInterval = 0
    var motionEMA: Double = 0
    var handConfidenceEMA: Double = 0
    var groundedEMA: Double = 0
    var trackerConfidenceEMA: Double = 0
    var lastSeenAt: Date?
    var lastPresentationTimestamp: CMTime?
    var lastCenter: CGPoint?
    var lastBoundingBox: CGRect?
    var restingAnchorCenter: CGPoint?
    var lastContext = ""
    var lastLocation = ""
    var lastSceneLabel = ""
    var lastLabelHint: String?
    var lastEventAt: Date?
    var lastPickupAt: Date?
    var lastPutDownAt: Date?
    var lastRestConfirmedAt: Date?
    var hasBeenSeen = false
    var interactionSpanOpen = false
    var didEmitCarryLoss = false
    var recentFeaturePrints: [VNFeaturePrintObservation] = []
}

private struct TrackedRegion {
    var candidateID: UUID
    var trackerConfidence: Double
    var boundingBox: CGRect
    var observation: VNDetectedObjectObservation
}

private struct FrameDetection {
    var candidateID: UUID
    var confidence: Double
    var boundingBox: CGRect
    var center: CGPoint
    var contextLabel: String
    var likelyLocation: String
    var sceneLabel: String
    var labelHint: String?
    var thumbnail: UIImage
    var handConfidence: Double
    var motionScore: Double
    var groundingScore: Double
    var trackerConfidence: Double
    var wasNewCandidate: Bool
    var featureObservation: VNFeaturePrintObservation?
    var trackingObservation: VNDetectedObjectObservation
}

private struct CandidateAssociation {
    var candidateID: UUID
    var overallScore: Double
    var featureScore: Double
    var geometryScore: Double
}

actor ObjectTrackingAnalyzer {
    private let similarityService: ImageSimilarityService

    private var candidateGallery: [UUID: [VNFeaturePrintObservation]] = [:]
    private var trackStates: [UUID: CandidateTrackState] = [:]
    private var sequenceHandler = VNSequenceRequestHandler()
    private var lastDiscoveryPresentationTimestamp: CMTime = .invalid

    private let maxTrackedCandidates = 10
    private let weakTrackerConfidenceThreshold = 0.18
    private let trackerConfidenceThreshold = 0.34
    private let shortHorizonFeatureThreshold = 0.33
    private let dormantReidentificationThreshold = 0.48
    private let currentFrameMergeThreshold = 0.40
    private let discoveryInterval: TimeInterval = 0.42
    private let stableVelocityThreshold = 0.08
    private let pickupVelocityThreshold = 0.13
    private let carryVelocityThreshold = 0.06
    private let strongHandConfidenceThreshold = 0.58
    private let continuingHandConfidenceThreshold = 0.40
    private let groundedScoreThreshold = 0.58
    private let restingConfirmationDuration: TimeInterval = 0.55
    private let putDownConfirmationDuration: TimeInterval = 0.50
    private let carryLossDelay: TimeInterval = 0.70
    private let reidentificationGap: TimeInterval = 0.35
    private let heartbeatInterval: TimeInterval = 1.8
    private let pickupSuppressionWindow: TimeInterval = 1.4

    init(similarityService: ImageSimilarityService = ImageSimilarityService()) {
        self.similarityService = similarityService
    }

    func prepare(candidates: [(id: UUID, referencePaths: [String])], imageLoader: (String) -> UIImage?) async {
        candidateGallery.removeAll()
        trackStates.removeAll()
        sequenceHandler = VNSequenceRequestHandler()
        lastDiscoveryPresentationTimestamp = .invalid

        for candidate in candidates {
            trackStates[candidate.id] = CandidateTrackState()
            for path in candidate.referencePaths {
                guard let image = imageLoader(path) else { continue }
                guard let featurePrint = try? similarityService.featurePrint(for: image) else { continue }
                appendFeaturePrint(featurePrint, to: candidate.id)
            }
        }
    }

    func reset() {
        candidateGallery.removeAll()
        trackStates.removeAll()
        sequenceHandler = VNSequenceRequestHandler()
        lastDiscoveryPresentationTimestamp = .invalid
    }

    func analyzeFrame(_ frame: CameraVideoFrame) async -> FrameAnalysisResult {
        let cgImage = frame.cgImage
        let hands = detectHands(in: cgImage)
        let trackedRegions = trackExistingCandidates(in: cgImage)

        var detectionsByCandidate = Dictionary(
            uniqueKeysWithValues: trackedRegions.compactMap { region in
                trackedDetection(from: region, in: cgImage, hands: hands).map { (region.candidateID, $0) }
            }
        )

        if shouldRunDiscovery(at: frame.presentationTimestamp, trackedRegions: trackedRegions) {
            let proposalDetections = detectObjects(
                in: cgImage,
                hands: hands,
                trackedRegions: trackedRegions,
                timestamp: frame.timestamp
            )

            for detection in proposalDetections {
                if let existing = detectionsByCandidate[detection.candidateID],
                   existing.confidence >= detection.confidence,
                   existing.trackerConfidence >= detection.trackerConfidence {
                    continue
                }
                detectionsByCandidate[detection.candidateID] = detection
            }

            lastDiscoveryPresentationTimestamp = frame.presentationTimestamp
        }

        let detections = Array(detectionsByCandidate.values)
        let detectionIDs = Set(detections.map(\.candidateID))
        let allCandidateIDs = detectionIDs.union(trackStates.keys).union(candidateGallery.keys)

        var events: [AnalyzerEventProposal] = []

        for candidateID in allCandidateIDs {
            let detection = detectionsByCandidate[candidateID]
            var state = trackStates[candidateID] ?? CandidateTrackState()
            let frameDelta = secondsSinceLastFrame(
                previous: state.lastPresentationTimestamp,
                current: frame.presentationTimestamp,
                fallback: 0.16
            )

            if let detection {
                let previousPhase = state.phase
                let priorMissingDuration = state.missingDuration
                let movement = detection.center.distance(to: state.lastCenter)
                let velocity = Double(movement) / max(frameDelta, 0.001)
                let smoothedVelocity = state.motionEMA == 0
                    ? velocity
                    : ((state.motionEMA * 0.62) + (velocity * 0.38))
                let smoothedHand = state.handConfidenceEMA == 0
                    ? detection.handConfidence
                    : ((state.handConfidenceEMA * 0.56) + (detection.handConfidence * 0.44))
                let smoothedGrounded = state.groundedEMA == 0
                    ? detection.groundingScore
                    : ((state.groundedEMA * 0.60) + (detection.groundingScore * 0.40))
                let trackerEMA = state.trackerConfidenceEMA == 0
                    ? detection.trackerConfidence
                    : ((state.trackerConfidenceEMA * 0.58) + (detection.trackerConfidence * 0.42))
                let handNearby = smoothedHand >= continuingHandConfidenceThreshold
                let stableNow = smoothedVelocity <= stableVelocityThreshold
                let restDisplacement = state.restingAnchorCenter.map { Double($0.distance(to: detection.center)) } ?? 0
                let restLift = state.restingAnchorCenter.map { Double(max(0, $0.y - detection.center.y)) } ?? 0

                state.motionEMA = smoothedVelocity
                state.handConfidenceEMA = smoothedHand
                state.groundedEMA = smoothedGrounded
                state.trackerConfidenceEMA = trackerEMA
                state.visibleStreak += 1
                state.missingStreak = 0
                state.missingDuration = 0
                state.activeObservation = detection.trackingObservation
                state.handContactDuration = handNearby
                    ? min(3.0, state.handContactDuration + frameDelta)
                    : max(0, state.handContactDuration - (frameDelta * 0.65))
                state.groundedDuration = smoothedGrounded >= groundedScoreThreshold
                    ? min(4.0, state.groundedDuration + frameDelta)
                    : max(0, state.groundedDuration - (frameDelta * 0.60))

                if smoothedGrounded >= 0.66 && smoothedHand < 0.30 {
                    state.restingAnchorCenter = state.restingAnchorCenter == nil
                        ? detection.center
                        : state.restingAnchorCenter?.interpolated(toward: detection.center, amount: 0.22)
                }

                if state.groundedDuration >= restingConfirmationDuration && !state.interactionSpanOpen {
                    state.lastRestConfirmedAt = frame.timestamp
                }

                if let featureObservation = detection.featureObservation {
                    state.recentFeaturePrints.insert(featureObservation, at: 0)
                    state.recentFeaturePrints = Array(state.recentFeaturePrints.prefix(8))
                    appendFeaturePrint(featureObservation, to: candidateID)
                }

                if !state.hasBeenSeen {
                    events.append(
                        AnalyzerEventProposal(
                            candidateID: candidateID,
                            timestamp: frame.timestamp,
                            eventType: .seen,
                            confidence: detection.confidence,
                            boundingBox: detection.boundingBox,
                            contextLabel: detection.contextLabel,
                            likelyLocation: detection.likelyLocation,
                            sceneLabel: detection.sceneLabel,
                            note: detection.wasNewCandidate
                                ? "Auto-discovered candidate entered the memory graph from on-device object proposals and tracking."
                                : "Candidate was seen again using prior visual evidence and track continuity.",
                            thumbnail: detection.thumbnail
                        )
                    )
                    state.phase = handNearby ? .inHand : (state.groundedDuration >= restingConfirmationDuration ? .resting : .unknown)
                    state.hasBeenSeen = true
                } else if previousPhase == .missing && priorMissingDuration >= reidentificationGap {
                    events.append(
                        AnalyzerEventProposal(
                            candidateID: candidateID,
                            timestamp: frame.timestamp,
                            eventType: .reidentified,
                            confidence: min(0.97, max(detection.confidence, trackerEMA)),
                            boundingBox: detection.boundingBox,
                            contextLabel: detection.contextLabel,
                            likelyLocation: detection.likelyLocation,
                            sceneLabel: detection.sceneLabel,
                            note: state.interactionSpanOpen
                                ? "Track continuity recovered after a short loss while the same interaction span remained open."
                                : "Candidate matched recent visual evidence after a short loss from view.",
                            thumbnail: detection.thumbnail
                        )
                    )
                    state.phase = handNearby ? .inHand : (state.groundedDuration >= restingConfirmationDuration ? .resting : .unknown)
                } else if shouldInferPickup(
                    timestamp: frame.timestamp,
                    handConfidence: smoothedHand,
                    velocity: smoothedVelocity,
                    restingDisplacement: restDisplacement,
                    restingLift: restLift,
                    state: state
                ) {
                    events.append(
                        AnalyzerEventProposal(
                            candidateID: candidateID,
                            timestamp: frame.timestamp,
                            eventType: .pickedUp,
                            confidence: pickupConfidence(
                                detectionConfidence: detection.confidence,
                                handConfidence: smoothedHand,
                                restingLift: restLift,
                                velocity: smoothedVelocity
                            ),
                            boundingBox: detection.boundingBox,
                            contextLabel: detection.contextLabel,
                            likelyLocation: detection.likelyLocation,
                            sceneLabel: detection.sceneLabel,
                            note: pickupNote(
                                handConfidence: smoothedHand,
                                velocity: smoothedVelocity,
                                restingDisplacement: restDisplacement,
                                restingLift: restLift
                            ),
                            thumbnail: detection.thumbnail
                        )
                    )
                    state.phase = .inHand
                    state.interactionSpanOpen = true
                    state.didEmitCarryLoss = false
                    state.lastPickupAt = frame.timestamp
                    state.groundedDuration = 0
                } else if state.interactionSpanOpen
                    && !handNearby
                    && stableNow
                    && state.groundedDuration >= putDownConfirmationDuration {
                    events.append(
                        AnalyzerEventProposal(
                            candidateID: candidateID,
                            timestamp: frame.timestamp,
                            eventType: .putDown,
                            confidence: min(0.97, max(detection.confidence, smoothedGrounded)),
                            boundingBox: detection.boundingBox,
                            contextLabel: detection.contextLabel,
                            likelyLocation: detection.likelyLocation,
                            sceneLabel: detection.sceneLabel,
                            note: "Tracked motion settled on the visible surface away from the hand long enough to close the interaction span.",
                            thumbnail: detection.thumbnail
                        )
                    )
                    state.phase = .resting
                    state.interactionSpanOpen = false
                    state.didEmitCarryLoss = false
                    state.lastPutDownAt = frame.timestamp
                    state.lastRestConfirmedAt = frame.timestamp
                } else if !state.interactionSpanOpen
                    && state.phase != .resting
                    && state.groundedDuration >= restingConfirmationDuration {
                    events.append(
                        AnalyzerEventProposal(
                            candidateID: candidateID,
                            timestamp: frame.timestamp,
                            eventType: .restingOnSurface,
                            confidence: min(0.95, max(detection.confidence, smoothedGrounded)),
                            boundingBox: detection.boundingBox,
                            contextLabel: detection.contextLabel,
                            likelyLocation: detection.likelyLocation,
                            sceneLabel: detection.sceneLabel,
                            note: "Candidate stayed stable on the visible surface without strong hand contact.",
                            thumbnail: detection.thumbnail
                        )
                    )
                    state.phase = .resting
                } else if state.interactionSpanOpen
                    && (handNearby || smoothedVelocity >= carryVelocityThreshold)
                    && shouldEmitHeartbeat(since: state.lastEventAt, at: frame.timestamp) {
                    events.append(
                        AnalyzerEventProposal(
                            candidateID: candidateID,
                            timestamp: frame.timestamp,
                            eventType: .inHand,
                            confidence: min(0.95, max(detection.confidence, smoothedHand)),
                            boundingBox: detection.boundingBox,
                            contextLabel: detection.contextLabel,
                            likelyLocation: detection.likelyLocation,
                            sceneLabel: detection.sceneLabel,
                            note: handNearby
                                ? "Tracked object remains close to the detected hand structure."
                                : "Tracked object is still moving through the same carry-like interaction span.",
                            thumbnail: detection.thumbnail
                        )
                    )
                    state.phase = .inHand
                }

                state.lastSeenAt = frame.timestamp
                state.lastPresentationTimestamp = frame.presentationTimestamp
                state.lastCenter = detection.center
                state.lastBoundingBox = detection.boundingBox
                state.lastContext = detection.contextLabel
                state.lastLocation = detection.likelyLocation
                state.lastSceneLabel = detection.sceneLabel
                state.lastLabelHint = detection.labelHint ?? state.lastLabelHint
            } else {
                state.visibleStreak = 0
                state.missingStreak += 1
                state.lastPresentationTimestamp = frame.presentationTimestamp
                state.missingDuration = state.lastSeenAt.map { frame.timestamp.timeIntervalSince($0) } ?? 0

                let carryLikely = state.interactionSpanOpen
                    || state.handConfidenceEMA >= continuingHandConfidenceThreshold
                    || state.lastPickupAt.map { frame.timestamp.timeIntervalSince($0) < 2.5 } == true

                if state.hasBeenSeen,
                   !state.didEmitCarryLoss,
                   carryLikely,
                   state.missingDuration >= carryLossDelay {
                    events.append(
                        AnalyzerEventProposal(
                            candidateID: candidateID,
                            timestamp: frame.timestamp,
                            eventType: .lostFromViewLikelyCarried,
                            confidence: min(0.82, max(0.58, state.handConfidenceEMA + 0.16)),
                            boundingBox: nil,
                            contextLabel: state.lastContext.isEmpty ? "Last stable context is still building." : state.lastContext,
                            likelyLocation: state.lastLocation.isEmpty ? "Last stable location is still building." : state.lastLocation,
                            sceneLabel: state.lastSceneLabel.isEmpty ? "on-device observation" : state.lastSceneLabel,
                            note: "The tracked object disappeared after a hand-linked interaction, so the same span remains open as possibly carried.",
                            thumbnail: nil
                        )
                    )
                    state.phase = .missing
                    state.didEmitCarryLoss = true
                } else if state.hasBeenSeen, state.missingDuration >= carryLossDelay {
                    state.phase = .missing
                }

                if state.missingDuration > 1.2 {
                    state.activeObservation = nil
                }
            }

            if let lastEvent = events.last(where: { $0.candidateID == candidateID }) {
                state.lastEventAt = lastEvent.timestamp
            }

            trackStates[candidateID] = state
        }

        let sightings = detections.map {
            AnalyzerSighting(
                candidateID: $0.candidateID,
                timestamp: frame.timestamp,
                confidence: $0.confidence,
                boundingBox: $0.boundingBox,
                contextLabel: $0.contextLabel,
                likelyLocation: $0.likelyLocation,
                sceneLabel: $0.sceneLabel,
                labelHint: $0.labelHint,
                thumbnail: $0.thumbnail,
                handConfidence: $0.handConfidence,
                motionScore: $0.motionScore,
                wasNewCandidate: $0.wasNewCandidate
            )
        }

        return FrameAnalysisResult(sightings: sightings, events: events)
    }

    private func trackExistingCandidates(in cgImage: CGImage) -> [TrackedRegion] {
        let trackedCandidates = trackStates
            .filter { _, state in
                state.activeObservation != nil && state.missingDuration < 2.4
            }
            .sorted { lhs, rhs in
                (lhs.value.lastSeenAt ?? .distantPast) > (rhs.value.lastSeenAt ?? .distantPast)
            }
            .prefix(maxTrackedCandidates)

        let pairedRequests = trackedCandidates.compactMap { candidateID, state -> (UUID, VNTrackObjectRequest)? in
            guard let observation = state.activeObservation else { return nil }
            let request = VNTrackObjectRequest(detectedObjectObservation: observation)
            if #available(iOS 13.0, *) {
                request.revision = VNTrackObjectRequestRevision2
            }
            request.trackingLevel = .accurate
            return (candidateID, request)
        }

        guard !pairedRequests.isEmpty else { return [] }

        do {
            try sequenceHandler.perform(pairedRequests.map(\.1), on: cgImage)
        } catch {
            return []
        }

        var trackedRegions: [TrackedRegion] = []
        for (candidateID, request) in pairedRequests {
            guard let observation = request.results?.first as? VNDetectedObjectObservation else { continue }

            var state = trackStates[candidateID] ?? CandidateTrackState()
            state.activeObservation = observation
            state.trackerConfidenceEMA = state.trackerConfidenceEMA == 0
                ? Double(observation.confidence)
                : ((state.trackerConfidenceEMA * 0.58) + (Double(observation.confidence) * 0.42))
            trackStates[candidateID] = state

            let boundingBox = topNormalizedRect(fromVisionRect: observation.boundingBox)
            guard isUsable(normalizedRect: boundingBox) else { continue }
            guard Double(observation.confidence) >= weakTrackerConfidenceThreshold else { continue }

            trackedRegions.append(
                TrackedRegion(
                    candidateID: candidateID,
                    trackerConfidence: Double(observation.confidence),
                    boundingBox: boundingBox,
                    observation: observation
                )
            )
        }

        return trackedRegions
    }

    private func trackedDetection(
        from trackedRegion: TrackedRegion,
        in cgImage: CGImage,
        hands: [HandObservation]
    ) -> FrameDetection? {
        guard trackedRegion.trackerConfidence >= trackerConfidenceThreshold else { return nil }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let pixelBox = pixelRect(fromNormalizedRect: trackedRegion.boundingBox, imageSize: imageSize).integral
        guard let crop = cgImage.cropping(to: pixelBox.intersection(CGRect(origin: .zero, size: imageSize))) else { return nil }

        let featureObservation = try? similarityService.featurePrint(for: crop)
        let center = CGPoint(x: trackedRegion.boundingBox.midX, y: trackedRegion.boundingBox.midY)
        let handMetrics = handMetrics(for: trackedRegion.boundingBox, center: center, hands: hands)
        let priorState = trackStates[trackedRegion.candidateID] ?? CandidateTrackState()
        let groundingScore = groundingScore(
            for: trackedRegion.boundingBox,
            handConfidence: handMetrics.confidence,
            velocity: priorState.motionEMA
        )
        let featureScore = featureObservation.map {
            bestFeatureScore(for: trackedRegion.candidateID, against: $0, state: priorState)
        } ?? 0
        let confidence = min(0.98, max(0.42, (trackedRegion.trackerConfidence * 0.58) + (featureScore * 0.42)))

        return FrameDetection(
            candidateID: trackedRegion.candidateID,
            confidence: confidence,
            boundingBox: trackedRegion.boundingBox,
            center: center,
            contextLabel: contextLabel(for: trackedRegion.boundingBox, handMetrics: handMetrics, groundingScore: groundingScore),
            likelyLocation: likelyLocation(for: trackedRegion.boundingBox, handMetrics: handMetrics, groundingScore: groundingScore),
            sceneLabel: hands.isEmpty ? "on-device observation" : "on-device observation with visible hand",
            labelHint: priorState.lastLabelHint,
            thumbnail: UIImage(cgImage: crop),
            handConfidence: handMetrics.confidence,
            motionScore: center.distance(to: priorState.lastCenter),
            groundingScore: groundingScore,
            trackerConfidence: trackedRegion.trackerConfidence,
            wasNewCandidate: false,
            featureObservation: featureObservation,
            trackingObservation: trackedRegion.observation
        )
    }

    private func shouldRunDiscovery(at presentationTimestamp: CMTime, trackedRegions: [TrackedRegion]) -> Bool {
        if !lastDiscoveryPresentationTimestamp.isValid {
            return true
        }

        if trackedRegions.isEmpty {
            return true
        }

        if trackStates.contains(where: { _, state in
            state.hasBeenSeen && state.missingStreak > 0 && state.missingDuration < 1.5
        }) {
            return true
        }

        let elapsed = secondsBetween(lastDiscoveryPresentationTimestamp, presentationTimestamp)
        return elapsed >= discoveryInterval
    }

    private func detectObjects(
        in cgImage: CGImage,
        hands: [HandObservation],
        trackedRegions: [TrackedRegion],
        timestamp: Date
    ) -> [FrameDetection] {
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let candidateRects = candidateRects(for: cgImage, imageSize: imageSize, hands: hands)
        var bestDetections: [UUID: FrameDetection] = [:]

        for rect in candidateRects {
            guard let crop = cgImage.cropping(to: rect.integral) else { continue }
            guard let cropObservation = try? similarityService.featurePrint(for: crop) else { continue }

            let normalizedRect = CGRect(
                x: rect.minX / imageSize.width,
                y: rect.minY / imageSize.height,
                width: rect.width / imageSize.width,
                height: rect.height / imageSize.height
            )
            guard isUsable(normalizedRect: normalizedRect) else { continue }

            let center = CGPoint(x: normalizedRect.midX, y: normalizedRect.midY)
            let handMetrics = handMetrics(for: normalizedRect, center: center, hands: hands)
            let priorTrackedRegion = bestTrackedRegion(for: normalizedRect, center: center, among: trackedRegions)
            let priorState = priorTrackedRegion.flatMap { trackStates[$0.candidateID] } ?? CandidateTrackState()
            let groundingScore = groundingScore(
                for: normalizedRect,
                handConfidence: handMetrics.confidence,
                velocity: priorState.motionEMA
            )

            let candidateID: UUID
            let confidence: Double
            let wasNewCandidate: Bool

            if let priorTrackedRegion {
                candidateID = priorTrackedRegion.candidateID
                confidence = min(0.98, max(0.46, priorTrackedRegion.trackerConfidence))
                wasNewCandidate = false
            } else if let association = bestCandidateMatch(
                for: cropObservation,
                boundingBox: normalizedRect,
                center: center,
                timestamp: timestamp,
                assignedCandidateIDs: Set(bestDetections.keys)
            ) {
                candidateID = association.candidateID
                confidence = min(0.99, max(0.46, association.overallScore))
                wasNewCandidate = false
            } else if let currentFrameCandidateID = currentFrameCandidate(
                for: cropObservation,
                boundingBox: normalizedRect,
                center: center,
                detections: bestDetections
            ) {
                candidateID = currentFrameCandidateID
                confidence = bestDetections[currentFrameCandidateID]?.confidence ?? 0.58
                wasNewCandidate = false
            } else {
                candidateID = UUID()
                confidence = candidateDiscoveryConfidence(
                    for: normalizedRect,
                    handMetrics: handMetrics,
                    groundingScore: groundingScore
                )
                wasNewCandidate = true
            }

            let detection = FrameDetection(
                candidateID: candidateID,
                confidence: confidence,
                boundingBox: normalizedRect,
                center: center,
                contextLabel: contextLabel(for: normalizedRect, handMetrics: handMetrics, groundingScore: groundingScore),
                likelyLocation: likelyLocation(for: normalizedRect, handMetrics: handMetrics, groundingScore: groundingScore),
                sceneLabel: hands.isEmpty ? "on-device observation" : "on-device observation with visible hand",
                labelHint: trackStates[candidateID]?.lastLabelHint,
                thumbnail: UIImage(cgImage: crop),
                handConfidence: handMetrics.confidence,
                motionScore: center.distance(to: trackStates[candidateID]?.lastCenter),
                groundingScore: groundingScore,
                trackerConfidence: priorTrackedRegion?.trackerConfidence ?? 0,
                wasNewCandidate: wasNewCandidate,
                featureObservation: cropObservation,
                trackingObservation: priorTrackedRegion?.observation
                    ?? VNDetectedObjectObservation(boundingBox: visionRect(fromTopNormalizedRect: normalizedRect))
            )

            if let existing = bestDetections[detection.candidateID], existing.confidence >= detection.confidence {
                continue
            }
            bestDetections[detection.candidateID] = detection
        }

        return Array(bestDetections.values)
    }

    private func candidateRects(
        for cgImage: CGImage,
        imageSize: CGSize,
        hands: [HandObservation]
    ) -> [CGRect] {
        var rects: [CGRect] = []

        rects.append(contentsOf: saliencyRects(in: cgImage, imageSize: imageSize))
        rects.append(contentsOf: foregroundInstanceRects(in: cgImage, imageSize: imageSize))

        if rects.isEmpty {
            rects.append(contentsOf: cropRects(for: imageSize))
        }

        for hand in hands {
            rects.append(pixelRect(fromNormalizedRect: hand.bounds.expanded(by: 0.28), imageSize: imageSize))
        }

        for state in trackStates.values where state.lastSeenAt != nil {
            if let lastBoundingBox = state.lastBoundingBox {
                rects.append(pixelRect(fromNormalizedRect: lastBoundingBox.expanded(by: 0.08), imageSize: imageSize))
                rects.append(pixelRect(fromNormalizedRect: lastBoundingBox.expanded(by: 0.18), imageSize: imageSize))
            }
        }

        return deduplicatedRects(rects, imageSize: imageSize)
    }

    private func saliencyRects(in cgImage: CGImage, imageSize: CGSize) -> [CGRect] {
        let objectnessRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        let attentionRequest = VNGenerateAttentionBasedSaliencyImageRequest()

        if #available(iOS 17.0, *) {
            objectnessRequest.revision = VNGenerateObjectnessBasedSaliencyImageRequestRevision2
            attentionRequest.revision = VNGenerateAttentionBasedSaliencyImageRequestRevision2
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([objectnessRequest, attentionRequest])
        } catch {
            return []
        }

        let observations = (objectnessRequest.results ?? []) + (attentionRequest.results ?? [])
        let normalizedRects = observations
            .flatMap { $0.salientObjects ?? [] }
            .map(\.boundingBox)
            .map(topNormalizedRect(fromVisionRect:))

        return normalizedRects.flatMap { rect in
            [
                pixelRect(fromNormalizedRect: rect, imageSize: imageSize),
                pixelRect(fromNormalizedRect: rect.expanded(by: 0.08), imageSize: imageSize)
            ]
        }
    }

    private func foregroundInstanceRects(in cgImage: CGImage, imageSize: CGSize) -> [CGRect] {
        guard #available(iOS 17.0, *) else { return [] }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observation = request.results?.first else { return [] }

        var rects: [CGRect] = []
        for instance in observation.allInstances.prefix(6) {
            guard let mask = try? observation.generateMask(forInstances: IndexSet(integer: instance)) else { continue }
            guard let normalizedRect = normalizedBoundingBox(fromFloatMask: mask) else { continue }

            rects.append(pixelRect(fromNormalizedRect: normalizedRect, imageSize: imageSize))
            rects.append(pixelRect(fromNormalizedRect: normalizedRect.expanded(by: 0.06), imageSize: imageSize))
        }

        return rects
    }

    private func normalizedBoundingBox(fromFloatMask pixelBuffer: CVPixelBuffer) -> CGRect? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var foundForeground = false

        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                if row[x] > 0.1 {
                    foundForeground = true
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard foundForeground, maxX > minX, maxY > minY else { return nil }

        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX) / CGFloat(width),
            height: CGFloat(maxY - minY) / CGFloat(height)
        )
    }

    private func detectHands(in cgImage: CGImage) -> [HandObservation] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return (request.results ?? []).compactMap { observation in
            let allPoints = (try? observation.recognizedPoints(.all))?
                .values
                .filter { $0.confidence > 0.16 }
                .map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) } ?? []

            guard !allPoints.isEmpty else { return nil }

            let fingertips: [CGPoint] = [
                VNHumanHandPoseObservation.JointName.thumbTip,
                VNHumanHandPoseObservation.JointName.indexTip,
                VNHumanHandPoseObservation.JointName.middleTip,
                VNHumanHandPoseObservation.JointName.ringTip,
                VNHumanHandPoseObservation.JointName.littleTip
            ].compactMap { jointName in
                guard let point = try? observation.recognizedPoint(jointName), point.confidence > 0.16 else {
                    return nil
                }
                return CGPoint(x: point.location.x, y: 1 - point.location.y)
            }

            let xs = allPoints.map(\.x)
            let ys = allPoints.map(\.y)
            let rect = CGRect(
                x: xs.min() ?? 0,
                y: ys.min() ?? 0,
                width: (xs.max() ?? 0) - (xs.min() ?? 0),
                height: (ys.max() ?? 0) - (ys.min() ?? 0)
            )

            guard !rect.isNull, !rect.isEmpty else { return nil }

            return HandObservation(
                bounds: rect,
                center: CGPoint(x: rect.midX, y: rect.midY),
                allPoints: allPoints,
                fingertips: fingertips
            )
        }
    }

    private func cropRects(for imageSize: CGSize) -> [CGRect] {
        let width = imageSize.width
        let height = imageSize.height
        let gridOrigins: [CGPoint] = [
            CGPoint(x: width * 0.08, y: height * 0.10),
            CGPoint(x: width * 0.30, y: height * 0.10),
            CGPoint(x: width * 0.52, y: height * 0.10),
            CGPoint(x: width * 0.08, y: height * 0.38),
            CGPoint(x: width * 0.30, y: height * 0.38),
            CGPoint(x: width * 0.52, y: height * 0.38)
        ]

        var rects: [CGRect] = []
        for multiplier in [0.26, 0.38, 0.50] {
            let side = min(width, height) * multiplier
            rects.append(contentsOf: gridOrigins.map { origin in
                CGRect(x: origin.x, y: origin.y, width: side, height: side)
            })
        }

        rects.append(CGRect(x: width * 0.14, y: height * 0.18, width: width * 0.66, height: height * 0.48))
        rects.append(CGRect(x: width * 0.08, y: height * 0.50, width: width * 0.84, height: height * 0.34))

        return rects
            .map { $0.intersection(CGRect(origin: .zero, size: imageSize)) }
            .filter { !$0.isNull && !$0.isEmpty }
    }

    private func handMetrics(for box: CGRect, center: CGPoint, hands: [HandObservation]) -> HandMetrics {
        var best = HandMetrics(confidence: 0, pointScore: 0, overlapScore: 0, distanceScore: 0)

        for hand in hands {
            let expandedBox = box.expanded(by: 0.12)
            let pointHits = hand.allPoints.filter { expandedBox.contains($0) }.count
            let fingertipHits = hand.fingertips.filter { expandedBox.contains($0) }.count
            let pointScore = min(1.0, (Double(pointHits) * 0.12) + (Double(fingertipHits) * 0.20))
            let overlapArea = box.intersection(hand.bounds.expanded(by: 0.20)).area
            let overlapScore = min(1.0, Double(overlapArea / max(box.area, 0.0001)))
            let distanceScore = max(0, 1 - Double(min(center.distance(to: hand.center) / 0.28, 1)))
            let confidence = min(1.0, (distanceScore * 0.40) + (overlapScore * 0.28) + (pointScore * 0.32))

            if confidence > best.confidence {
                best = HandMetrics(
                    confidence: confidence,
                    pointScore: pointScore,
                    overlapScore: overlapScore,
                    distanceScore: distanceScore
                )
            }
        }

        return best
    }

    private func groundingScore(for boundingBox: CGRect, handConfidence: Double, velocity: Double) -> Double {
        let lowerFrameScore = max(0, min((Double(boundingBox.maxY) - 0.46) / 0.34, 1))
        let stabilityScore = max(0, 1 - min(velocity / 0.18, 1))
        let handAwayScore = max(0, 1 - handConfidence)
        return min(1.0, (lowerFrameScore * 0.46) + (stabilityScore * 0.34) + (handAwayScore * 0.20))
    }

    private func contextLabel(for boundingBox: CGRect, handMetrics: HandMetrics, groundingScore: Double) -> String {
        if handMetrics.confidence >= strongHandConfidenceThreshold {
            return "near your hand"
        }

        if groundingScore >= groundedScoreThreshold {
            return "resting on the \(surfacePhrase(for: boundingBox.midX))"
        }

        if boundingBox.midY < 0.24 {
            return "high in the frame"
        }

        return "mid-frame in open view"
    }

    private func likelyLocation(for boundingBox: CGRect, handMetrics: HandMetrics, groundingScore: Double) -> String {
        if handMetrics.confidence >= strongHandConfidenceThreshold {
            return "near your hand"
        }

        if groundingScore >= groundedScoreThreshold {
            return surfacePhrase(for: boundingBox.midX)
        }

        if boundingBox.midY < 0.24 {
            return "upper area of the frame"
        }

        return "mid-frame"
    }

    private func shouldEmitHeartbeat(since lastEventAt: Date?, at timestamp: Date) -> Bool {
        guard let lastEventAt else { return true }
        return timestamp.timeIntervalSince(lastEventAt) >= heartbeatInterval
    }

    private func shouldInferPickup(
        timestamp: Date,
        handConfidence: Double,
        velocity: Double,
        restingDisplacement: Double,
        restingLift: Double,
        state: CandidateTrackState
    ) -> Bool {
        guard !state.interactionSpanOpen else { return false }
        guard state.visibleStreak >= 3 else { return false }
        let recentlyResting = state.lastRestConfirmedAt.map { timestamp.timeIntervalSince($0) < 2.0 } == true
        guard state.phase == .resting || recentlyResting else { return false }

        if let lastPickupAt = state.lastPickupAt,
           timestamp.timeIntervalSince(lastPickupAt) < pickupSuppressionWindow {
            return false
        }

        let contactSupported = handConfidence >= strongHandConfidenceThreshold || state.handContactDuration >= 0.20
        let leftRestAnchor = restingDisplacement > 0.050 || restingLift > 0.028
        let movementSupported = velocity >= pickupVelocityThreshold || restingLift > 0.034
        return contactSupported && leftRestAnchor && movementSupported
    }

    private func pickupConfidence(
        detectionConfidence: Double,
        handConfidence: Double,
        restingLift: Double,
        velocity: Double
    ) -> Double {
        let liftScore = min(1.0, restingLift / 0.08)
        let motionScore = min(1.0, velocity / 0.24)
        return min(0.98, max(0.56, (detectionConfidence * 0.46) + (handConfidence * 0.28) + (liftScore * 0.14) + (motionScore * 0.12)))
    }

    private func pickupNote(
        handConfidence: Double,
        velocity: Double,
        restingDisplacement: Double,
        restingLift: Double
    ) -> String {
        if restingLift > 0.03 {
            return "Tracked object lifted away from its recent resting anchor while hand evidence stayed close."
        }

        if handConfidence >= strongHandConfidenceThreshold {
            return "Tracked object broke from a stable resting anchor while hand evidence remained strong."
        }

        if velocity >= pickupVelocityThreshold {
            return "Tracked motion accelerated away from a recent resting anchor in a carry-like pattern."
        }

        return "Tracked object left its recent resting anchor in a way that looks like a pickup."
    }

    private func bestTrackedRegion(
        for boundingBox: CGRect,
        center: CGPoint,
        among trackedRegions: [TrackedRegion]
    ) -> TrackedRegion? {
        trackedRegions
            .filter { region in
                region.boundingBox.iou(with: boundingBox) > 0.45 || center.distance(to: CGPoint(x: region.boundingBox.midX, y: region.boundingBox.midY)) < 0.08
            }
            .max { lhs, rhs in
                lhs.boundingBox.iou(with: boundingBox) < rhs.boundingBox.iou(with: boundingBox)
            }
    }

    private func bestCandidateMatch(
        for featureObservation: VNFeaturePrintObservation,
        boundingBox: CGRect,
        center: CGPoint,
        timestamp: Date,
        assignedCandidateIDs: Set<UUID>
    ) -> CandidateAssociation? {
        var bestAssociation: CandidateAssociation?

        for candidateID in Set(candidateGallery.keys).union(trackStates.keys) where !assignedCandidateIDs.contains(candidateID) {
            let state = trackStates[candidateID] ?? CandidateTrackState()
            let timeSinceSeen = state.lastSeenAt.map { timestamp.timeIntervalSince($0) } ?? .infinity
            let featureScore = bestFeatureScore(for: candidateID, against: featureObservation, state: state)
            let geometryScore = geometryScore(for: state, boundingBox: boundingBox, center: center, timeSinceSeen: timeSinceSeen)

            let overallScore: Double
            if timeSinceSeen < 1.5 {
                overallScore = (featureScore * 0.56) + (geometryScore * 0.44)
            } else {
                overallScore = (featureScore * 0.84) + (geometryScore * 0.16)
            }

            let qualifies: Bool
            if timeSinceSeen < 1.5 {
                qualifies = featureScore >= shortHorizonFeatureThreshold || geometryScore >= 0.62
            } else {
                qualifies = featureScore >= dormantReidentificationThreshold
            }

            guard qualifies else { continue }

            let association = CandidateAssociation(
                candidateID: candidateID,
                overallScore: overallScore,
                featureScore: featureScore,
                geometryScore: geometryScore
            )

            if let currentBest = bestAssociation {
                if association.overallScore > currentBest.overallScore {
                    bestAssociation = association
                }
            } else {
                bestAssociation = association
            }
        }

        return bestAssociation
    }

    private func bestFeatureScore(
        for candidateID: UUID,
        against observation: VNFeaturePrintObservation,
        state: CandidateTrackState
    ) -> Double {
        let references = (candidateGallery[candidateID] ?? []) + state.recentFeaturePrints
        guard !references.isEmpty else { return 0 }

        var bestScore = 0.0
        for reference in references.prefix(10) {
            guard let distance = try? similarityService.distance(between: reference, and: observation) else {
                continue
            }
            bestScore = max(bestScore, 1 / (1 + distance))
        }

        return bestScore
    }

    private func geometryScore(
        for state: CandidateTrackState,
        boundingBox: CGRect,
        center: CGPoint,
        timeSinceSeen: TimeInterval
    ) -> Double {
        guard let lastBoundingBox = state.lastBoundingBox else { return 0 }

        let iouScore = lastBoundingBox.iou(with: boundingBox)
        let distanceScore = max(0, 1 - Double(min(center.distance(to: state.lastCenter) / 0.20, 1)))
        let freshness = timeSinceSeen < 1.5 ? 1.0 : max(0.22, 1 - (timeSinceSeen / 5.0))
        return ((iouScore * 0.58) + (distanceScore * 0.42)) * freshness
    }

    private func currentFrameCandidate(
        for featureObservation: VNFeaturePrintObservation,
        boundingBox: CGRect,
        center: CGPoint,
        detections: [UUID: FrameDetection]
    ) -> UUID? {
        for detection in detections.values {
            let iouScore = detection.boundingBox.iou(with: boundingBox)
            let distance = center.distance(to: detection.center)
            let similarity = detection.featureObservation.flatMap {
                try? similarityService.distance(between: $0, and: featureObservation)
            }
            .map { 1 / (1 + $0) } ?? 0

            if iouScore > 0.40 || (distance < 0.10 && similarity >= currentFrameMergeThreshold) {
                return detection.candidateID
            }
        }

        return nil
    }

    private func candidateDiscoveryConfidence(for boundingBox: CGRect, handMetrics: HandMetrics, groundingScore: Double) -> Double {
        let area = boundingBox.area
        let sizeScore: Double
        switch area {
        case 0.02...0.24:
            sizeScore = 1.0
        case 0.012...0.36:
            sizeScore = 0.82
        default:
            sizeScore = 0.64
        }

        let edgePenalty = boundingBox.minX < 0.02
            || boundingBox.maxX > 0.98
            || boundingBox.minY < 0.02
            || boundingBox.maxY > 0.98
            ? 0.86
            : 1.0

        return min(0.86, max(0.50, ((0.44 + (sizeScore * 0.22) + (groundingScore * 0.14) + (handMetrics.confidence * 0.08)) * edgePenalty)))
    }

    private func appendFeaturePrint(_ featurePrint: VNFeaturePrintObservation, to candidateID: UUID) {
        var gallery = candidateGallery[candidateID] ?? []
        gallery.insert(featurePrint, at: 0)
        candidateGallery[candidateID] = Array(gallery.prefix(12))
    }

    private func secondsSinceLastFrame(previous: CMTime?, current: CMTime, fallback: TimeInterval) -> TimeInterval {
        guard let previous, previous.isValid, current.isValid else { return fallback }
        let seconds = CMTimeGetSeconds(CMTimeSubtract(current, previous))
        guard seconds.isFinite, seconds > 0 else { return fallback }
        return seconds
    }

    private func secondsBetween(_ lhs: CMTime, _ rhs: CMTime) -> TimeInterval {
        let seconds = CMTimeGetSeconds(CMTimeSubtract(rhs, lhs))
        guard seconds.isFinite else { return 0 }
        return max(0, seconds)
    }

    private func horizontalPhrase(for x: CGFloat) -> String {
        if x < 0.32 {
            return "left"
        }
        if x > 0.68 {
            return "right"
        }
        return "center"
    }

    private func surfacePhrase(for x: CGFloat) -> String {
        switch horizontalPhrase(for: x) {
        case "left":
            return "left side of the visible surface"
        case "right":
            return "right side of the visible surface"
        default:
            return "center of the visible surface"
        }
    }

    private func topNormalizedRect(fromVisionRect rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: 1 - rect.origin.y - rect.size.height,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    private func visionRect(fromTopNormalizedRect rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: 1 - rect.origin.y - rect.size.height,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    private func pixelRect(fromNormalizedRect rect: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * imageSize.width,
            y: rect.minY * imageSize.height,
            width: rect.width * imageSize.width,
            height: rect.height * imageSize.height
        )
    }

    private func deduplicatedRects(_ rects: [CGRect], imageSize: CGSize) -> [CGRect] {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        var deduplicated: [CGRect] = []

        for rect in rects {
            let clampedRect = rect.intersection(imageBounds)
            let normalizedArea = (clampedRect.width * clampedRect.height) / max(imageSize.width * imageSize.height, 1)
            guard
                !clampedRect.isNull,
                !clampedRect.isEmpty,
                clampedRect.width > 40,
                clampedRect.height > 40,
                normalizedArea > 0.010,
                normalizedArea < 0.48
            else {
                continue
            }

            let isDuplicate = deduplicated.contains { existing in
                existing.intersection(clampedRect).area / max(existing.area, clampedRect.area) > 0.70
            }

            if !isDuplicate {
                deduplicated.append(clampedRect)
            }
        }

        return Array(deduplicated.prefix(24))
    }

    private func isUsable(normalizedRect: CGRect) -> Bool {
        guard !normalizedRect.isNull, !normalizedRect.isEmpty else { return false }
        guard normalizedRect.minX >= 0, normalizedRect.minY >= 0 else { return false }
        guard normalizedRect.maxX <= 1, normalizedRect.maxY <= 1 else { return false }

        let area = normalizedRect.area
        return area > 0.010 && area < 0.48
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

    func expanded(by amount: CGFloat) -> CGRect {
        insetBy(dx: -width * amount, dy: -height * amount)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint?) -> CGFloat {
        guard let other else { return 0 }
        let dx = x - other.x
        let dy = y - other.y
        return sqrt((dx * dx) + (dy * dy))
    }

    func interpolated(toward other: CGPoint, amount: CGFloat) -> CGPoint {
        CGPoint(
            x: x + ((other.x - x) * amount),
            y: y + ((other.y - y) * amount)
        )
    }
}
