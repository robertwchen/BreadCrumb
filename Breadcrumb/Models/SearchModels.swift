import Foundation

struct LastKnownStateSnapshot: Hashable, Sendable {
    var candidateID: UUID
    var trackedObjectID: UUID?
    var lastEventType: ObservationEventType
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
}

struct EventSnapshot: Identifiable, Hashable, Sendable {
    var id: UUID
    var sessionID: UUID
    var candidateID: UUID
    var trackedObjectID: UUID?
    var timestamp: Date
    var eventType: ObservationEventType
    var confidence: Double
    var boundingBox: RectData?
    var contextLabel: String?
    var sceneLabel: String?
    var likelyLocation: String?
    var evidencePath: String?
    var note: String
    var inferenceSource: EventInferenceSource
}

struct HandInteractionSnapshot: Identifiable, Hashable, Sendable {
    var id: UUID
    var candidateID: UUID
    var trackedObjectID: UUID?
    var sessionID: UUID
    var pickupTimestamp: Date
    var putDownTimestamp: Date?
    var contextSummary: String

    var duration: TimeInterval? {
        guard let putDownTimestamp else { return nil }
        return putDownTimestamp.timeIntervalSince(pickupTimestamp)
    }
}

struct SessionSnapshot: Identifiable, Hashable, Sendable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var status: TrackingSessionStatus
    var sessionLabel: String
    var analyzedFrameCount: Int
    var localCandidateCount: Int
    var remoteRefinementEnabled: Bool
    var backendStatusNote: String?
}

struct CandidateSummary: Identifiable, Hashable, Sendable {
    var id: UUID
    var promotedTrackedObjectID: UUID?
    var title: String
    var subtitle: String
    var candidateStatus: CandidateStatus
    var observationCount: Int
    var clusterConfidence: Double
    var latestEvidencePath: String?
    var lastState: LastKnownStateSnapshot?
    var recentEvents: [EventSnapshot]
    var isPinned: Bool

    var isPromoted: Bool {
        promotedTrackedObjectID != nil
    }

    var isPossiblyLost: Bool {
        lastState?.isPossiblyLost == true
    }

    var lastSeenAt: Date? {
        lastState?.lastSeenAt
    }

    var lastEventTitle: String {
        lastState?.lastEventType.title ?? "No events yet"
    }
}

struct ObjectStatusSummary: Identifiable, Hashable, Sendable {
    var id: UUID
    var objectID: UUID
    var candidateID: UUID?
    var displayName: String
    var userNotes: String
    var primaryReferenceImagePath: String?
    var latestEvidencePath: String?
    var lastState: LastKnownStateSnapshot?
    var recentEvents: [EventSnapshot]
    var interactions: [HandInteractionSnapshot]
    var isPinned: Bool

    var isPossiblyLost: Bool {
        lastState?.isPossiblyLost == true
    }

    var lastHandledAt: Date? {
        if let openInteraction = interactions.first(where: { $0.putDownTimestamp == nil }) {
            return openInteraction.pickupTimestamp
        }

        if let interaction = interactions.first {
            return interaction.putDownTimestamp ?? interaction.pickupTimestamp
        }

        switch (lastState?.lastPickupAt, lastState?.lastPutDownAt) {
        case let (pickup?, putDown?):
            return max(pickup, putDown)
        case let (pickup?, nil):
            return pickup
        case let (nil, putDown?):
            return putDown
        case (nil, nil):
            return nil
        }
    }

    var isRecentlyHandled: Bool {
        guard let lastHandledAt else { return false }
        return Date().timeIntervalSince(lastHandledAt) < (6 * 60 * 60)
    }
}

struct CandidateHistorySummary: Hashable, Sendable {
    var candidateSummary: CandidateSummary
    var recentEvents: [EventSnapshot]
}

struct ObjectHistorySummary: Hashable, Sendable {
    var objectSummary: ObjectStatusSummary
    var recentEvents: [EventSnapshot]
    var interactions: [HandInteractionSnapshot]
}

struct LiveCandidateStatus: Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var isPromoted: Bool
    var eventTitle: String
    var confidence: Double
    var contextSummary: String
    var likelyLocation: String
    var boundingBox: RectData?
    var uncertaintySummary: String
}
