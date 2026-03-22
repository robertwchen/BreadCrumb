import CoreGraphics
import Foundation
import SwiftData

enum CandidateStatus: String, Codable, CaseIterable, Sendable {
    case inbox
    case promoted
    case dismissed
}

enum ObservationSourceKind: String, Codable, CaseIterable, Sendable {
    case localVision
    case backendRefinement
    case manualCorrection
}

enum EventInferenceSource: String, Codable, CaseIterable, Sendable {
    case localStateMachine
    case backendRefinement
    case userCorrection
}

@Model
final class ObjectCandidate {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var lastSeenAt: Date
    var observationCount: Int
    var candidateStatusRaw: String
    var clusterConfidence: Double
    var embeddingDigest: String?
    var latestBoundingBox: RectData?
    var latestContextSummary: String
    var latestEvidenceThumbnailPath: String?
    var latestSceneLabel: String?
    var latestLocationSummary: String?
    var latestLabelHint: String?
    var latestRemoteTrackID: String?
    var promotedTrackedObjectID: UUID?
    var manualReferenceImagePaths: String
    var lastEventTypeRaw: String?
    var lastEventConfidence: Double
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        lastSeenAt: Date,
        observationCount: Int = 0,
        candidateStatus: CandidateStatus = .inbox,
        clusterConfidence: Double = 0,
        embeddingDigest: String? = nil,
        latestBoundingBox: RectData? = nil,
        latestContextSummary: String = "No context yet",
        latestEvidenceThumbnailPath: String? = nil,
        latestSceneLabel: String? = nil,
        latestLocationSummary: String? = nil,
        latestLabelHint: String? = nil,
        latestRemoteTrackID: String? = nil,
        promotedTrackedObjectID: UUID? = nil,
        manualReferenceImagePaths: String = "",
        lastEventTypeRaw: String? = nil,
        lastEventConfidence: Double = 0,
        isPinned: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.observationCount = observationCount
        self.candidateStatusRaw = candidateStatus.rawValue
        self.clusterConfidence = clusterConfidence
        self.embeddingDigest = embeddingDigest
        self.latestBoundingBox = latestBoundingBox
        self.latestContextSummary = latestContextSummary
        self.latestEvidenceThumbnailPath = latestEvidenceThumbnailPath
        self.latestSceneLabel = latestSceneLabel
        self.latestLocationSummary = latestLocationSummary
        self.latestLabelHint = latestLabelHint
        self.latestRemoteTrackID = latestRemoteTrackID
        self.promotedTrackedObjectID = promotedTrackedObjectID
        self.manualReferenceImagePaths = manualReferenceImagePaths
        self.lastEventTypeRaw = lastEventTypeRaw
        self.lastEventConfidence = lastEventConfidence
        self.isPinned = isPinned
    }

    var candidateStatus: CandidateStatus {
        get { CandidateStatus(rawValue: candidateStatusRaw) ?? .inbox }
        set { candidateStatusRaw = newValue.rawValue }
    }

    var lastEventType: ObservationEventType? {
        get { lastEventTypeRaw.flatMap(ObservationEventType.init(rawValue:)) }
        set { lastEventTypeRaw = newValue?.rawValue }
    }

    var referenceImagePaths: [String] {
        decodePathList(manualReferenceImagePaths)
    }

    var allReferenceImagePaths: [String] {
        let automatic = latestEvidenceThumbnailPath.map { [$0] } ?? []
        return automatic + referenceImagePaths
    }

    func appendReferenceImagePath(_ path: String) {
        var paths = referenceImagePaths
        guard !paths.contains(path) else { return }
        paths.append(path)
        manualReferenceImagePaths = encodePathList(paths)
    }
}

@Model
final class TrackedObject {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var userNotes: String
    var createdAt: Date
    var candidateOriginID: UUID?
    var manualReferenceImagePaths: String
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        userNotes: String = "",
        createdAt: Date = Date(),
        candidateOriginID: UUID? = nil,
        manualReferenceImagePaths: String = "",
        isPinned: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.userNotes = userNotes
        self.createdAt = createdAt
        self.candidateOriginID = candidateOriginID
        self.manualReferenceImagePaths = manualReferenceImagePaths
        self.isPinned = isPinned
    }

    var referenceImagePaths: [String] {
        decodePathList(manualReferenceImagePaths)
    }

    var primaryReferenceImagePath: String? {
        referenceImagePaths.first
    }

    func appendReferenceImagePath(_ path: String) {
        var paths = referenceImagePaths
        guard !paths.contains(path) else { return }
        paths.append(path)
        manualReferenceImagePaths = encodePathList(paths)
    }
}

@Model
final class LastKnownObjectState {
    @Attribute(.unique) var id: UUID
    var candidateID: UUID
    var trackedObjectID: UUID?
    var lastEventTypeRaw: String
    var lastSeenAt: Date
    var lastContextSummary: String
    var likelyLocation: String
    var isPossiblyLost: Bool
    var confidence: Double
    var lastBoundingBox: RectData?
    var lastThumbnailPath: String?
    var lastSessionID: UUID?
    var lastPickupAt: Date?
    var lastPutDownAt: Date?

    init(
        id: UUID = UUID(),
        candidateID: UUID,
        trackedObjectID: UUID? = nil,
        lastEventType: ObservationEventType,
        lastSeenAt: Date,
        lastContextSummary: String,
        likelyLocation: String,
        isPossiblyLost: Bool,
        confidence: Double,
        lastBoundingBox: RectData? = nil,
        lastThumbnailPath: String? = nil,
        lastSessionID: UUID? = nil,
        lastPickupAt: Date? = nil,
        lastPutDownAt: Date? = nil
    ) {
        self.id = id
        self.candidateID = candidateID
        self.trackedObjectID = trackedObjectID
        self.lastEventTypeRaw = lastEventType.rawValue
        self.lastSeenAt = lastSeenAt
        self.lastContextSummary = lastContextSummary
        self.likelyLocation = likelyLocation
        self.isPossiblyLost = isPossiblyLost
        self.confidence = confidence
        self.lastBoundingBox = lastBoundingBox
        self.lastThumbnailPath = lastThumbnailPath
        self.lastSessionID = lastSessionID
        self.lastPickupAt = lastPickupAt
        self.lastPutDownAt = lastPutDownAt
    }

    var lastEventType: ObservationEventType {
        get { ObservationEventType(rawValue: lastEventTypeRaw) ?? .seen }
        set { lastEventTypeRaw = newValue.rawValue }
    }
}

@Model
final class HandInteractionRecord {
    @Attribute(.unique) var id: UUID
    var candidateID: UUID
    var trackedObjectID: UUID?
    var sessionID: UUID
    var pickupTimestamp: Date
    var putDownTimestamp: Date?
    var contextSummary: String

    init(
        id: UUID = UUID(),
        candidateID: UUID,
        trackedObjectID: UUID? = nil,
        sessionID: UUID,
        pickupTimestamp: Date,
        putDownTimestamp: Date? = nil,
        contextSummary: String
    ) {
        self.id = id
        self.candidateID = candidateID
        self.trackedObjectID = trackedObjectID
        self.sessionID = sessionID
        self.pickupTimestamp = pickupTimestamp
        self.putDownTimestamp = putDownTimestamp
        self.contextSummary = contextSummary
    }

    var duration: TimeInterval? {
        guard let putDownTimestamp else { return nil }
        return putDownTimestamp.timeIntervalSince(pickupTimestamp)
    }
}

struct RectData: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

func encodePathList(_ paths: [String]) -> String {
    paths.joined(separator: "\n")
}

func decodePathList(_ raw: String) -> [String] {
    raw
        .split(separator: "\n")
        .map(String.init)
        .filter { !$0.isEmpty }
}
