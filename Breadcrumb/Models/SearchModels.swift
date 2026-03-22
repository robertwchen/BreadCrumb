import Foundation

enum MatchEvidence: Hashable, Sendable {
    case manualConfirmation
    case visualSimilarity(distance: Double)
}

struct SearchMatch: Identifiable, Hashable, Sendable {
    let id = UUID()
    var snapshot: TimelineSnapshot
    var evidence: MatchEvidence
    var score: Double

    var title: String {
        switch evidence {
        case .manualConfirmation:
            return "Latest confirmed sighting"
        case .visualSimilarity:
            return "Best visual match"
        }
    }

    var subtitle: String {
        switch evidence {
        case .manualConfirmation:
            return "You marked this item as visible in this capture."
        case .visualSimilarity:
            return "Matched on-device against the item's reference photos."
        }
    }
}

struct SearchResult: Hashable, Sendable {
    var item: TrackedItem
    var primaryMatch: SearchMatch
    var contextStrip: [TimelineSnapshot]
    var alternativeMatches: [SearchMatch]
}
