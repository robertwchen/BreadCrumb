import Foundation
import SwiftData

enum TrackingSessionStatus: String, Codable, Hashable, Sendable {
    case recording
    case completed
    case failed
}

enum ObservationEventType: String, Codable, Hashable, Sendable, CaseIterable {
    case seen
    case restingOnSurface
    case pickedUp
    case inHand
    case lostFromViewLikelyCarried
    case reidentified
    case putDown

    var title: String {
        switch self {
        case .seen:
            return "Seen"
        case .restingOnSurface:
            return "Resting on surface"
        case .pickedUp:
            return "Picked up"
        case .inHand:
            return "In hand"
        case .lostFromViewLikelyCarried:
            return "Possibly carried"
        case .reidentified:
            return "Reidentified"
        case .putDown:
            return "Put down"
        }
    }

    var impliesMissingState: Bool {
        self == .lostFromViewLikelyCarried
    }

    var isHandlingEvent: Bool {
        switch self {
        case .pickedUp, .inHand, .putDown:
            return true
        case .seen, .restingOnSurface, .lostFromViewLikelyCarried, .reidentified:
            return false
        }
    }
}

@Model
final class TrackingSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var sessionLabel: String
    var analyzedFrameCount: Int
    var localCandidateCount: Int
    var remoteRefinementEnabled: Bool
    var backendStatusNote: String?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: TrackingSessionStatus = .recording,
        sessionLabel: String,
        analyzedFrameCount: Int = 0,
        localCandidateCount: Int = 0,
        remoteRefinementEnabled: Bool = false,
        backendStatusNote: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.statusRaw = status.rawValue
        self.sessionLabel = sessionLabel
        self.analyzedFrameCount = analyzedFrameCount
        self.localCandidateCount = localCandidateCount
        self.remoteRefinementEnabled = remoteRefinementEnabled
        self.backendStatusNote = backendStatusNote
    }

    var status: TrackingSessionStatus {
        get { TrackingSessionStatus(rawValue: statusRaw) ?? .recording }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class ObservationRecord {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var candidateID: UUID
    var trackedObjectID: UUID?
    var timestamp: Date
    var boundingBox: RectData?
    var confidence: Double
    var sourceRaw: String
    var sceneLabel: String?
    var contextLabel: String?
    var likelyLocation: String?
    var evidencePath: String?
    var embeddingDigest: String?
    var remoteTrackID: String?
    var handConfidence: Double
    var motionScore: Double
    var labelHint: String?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        candidateID: UUID,
        trackedObjectID: UUID? = nil,
        timestamp: Date,
        boundingBox: RectData? = nil,
        confidence: Double,
        source: ObservationSourceKind,
        sceneLabel: String? = nil,
        contextLabel: String? = nil,
        likelyLocation: String? = nil,
        evidencePath: String? = nil,
        embeddingDigest: String? = nil,
        remoteTrackID: String? = nil,
        handConfidence: Double = 0,
        motionScore: Double = 0,
        labelHint: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.candidateID = candidateID
        self.trackedObjectID = trackedObjectID
        self.timestamp = timestamp
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.sourceRaw = source.rawValue
        self.sceneLabel = sceneLabel
        self.contextLabel = contextLabel
        self.likelyLocation = likelyLocation
        self.evidencePath = evidencePath
        self.embeddingDigest = embeddingDigest
        self.remoteTrackID = remoteTrackID
        self.handConfidence = handConfidence
        self.motionScore = motionScore
        self.labelHint = labelHint
    }

    var source: ObservationSourceKind {
        get { ObservationSourceKind(rawValue: sourceRaw) ?? .localVision }
        set { sourceRaw = newValue.rawValue }
    }
}

@Model
final class ObjectObservationEvent {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var candidateID: UUID
    var trackedObjectID: UUID?
    var timestamp: Date
    var eventTypeRaw: String
    var confidence: Double
    var boundingBox: RectData?
    var contextLabel: String?
    var sceneLabel: String?
    var likelyLocation: String?
    var evidencePath: String?
    var note: String
    var inferenceSourceRaw: String

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        candidateID: UUID,
        trackedObjectID: UUID? = nil,
        timestamp: Date,
        eventType: ObservationEventType,
        confidence: Double,
        boundingBox: RectData? = nil,
        contextLabel: String? = nil,
        sceneLabel: String? = nil,
        likelyLocation: String? = nil,
        evidencePath: String? = nil,
        note: String,
        inferenceSource: EventInferenceSource = .localStateMachine
    ) {
        self.id = id
        self.sessionID = sessionID
        self.candidateID = candidateID
        self.trackedObjectID = trackedObjectID
        self.timestamp = timestamp
        self.eventTypeRaw = eventType.rawValue
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.contextLabel = contextLabel
        self.sceneLabel = sceneLabel
        self.likelyLocation = likelyLocation
        self.evidencePath = evidencePath
        self.note = note
        self.inferenceSourceRaw = inferenceSource.rawValue
    }

    var eventType: ObservationEventType {
        get { ObservationEventType(rawValue: eventTypeRaw) ?? .seen }
        set { eventTypeRaw = newValue.rawValue }
    }

    var inferenceSource: EventInferenceSource {
        get { EventInferenceSource(rawValue: inferenceSourceRaw) ?? .localStateMachine }
        set { inferenceSourceRaw = newValue.rawValue }
    }
}
