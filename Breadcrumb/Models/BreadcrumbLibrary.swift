import Foundation

struct BreadcrumbCounts: Hashable, Sendable {
    var trackedObjectCount: Int
    var inboxCandidateCount: Int
    var promotedCandidateCount: Int
    var sessionCount: Int
    var eventCount: Int
    var possibleMissingCount: Int
    var recentlyHandledCount: Int
}
