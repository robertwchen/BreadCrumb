import Foundation

final class SearchService: @unchecked Sendable {
    private let store: LibraryStore
    private let similarityService: ImageSimilarityService

    init(
        store: LibraryStore,
        similarityService: ImageSimilarityService = ImageSimilarityService()
    ) {
        self.store = store
        self.similarityService = similarityService
    }

    func findLastSeen(for item: TrackedItem, in library: BreadcrumbLibrary) -> SearchResult? {
        let orderedSnapshots = library.orderedSnapshotsDescending()
        guard !orderedSnapshots.isEmpty else { return nil }

        let manualMatches = orderedSnapshots
            .filter { $0.visibleItemIDs.contains(item.id) }
            .map {
                SearchMatch(
                    snapshot: $0,
                    evidence: .manualConfirmation,
                    score: 1.0
                )
            }

        let primaryManual = manualMatches.first
        let visualMatches = buildVisualMatches(for: item, snapshots: orderedSnapshots)

        let primaryMatch: SearchMatch?
        let alternatives: [SearchMatch]

        if let primaryManual {
            primaryMatch = primaryManual
            alternatives = Array(manualMatches.dropFirst()) + Array(visualMatches.prefix(3))
        } else {
            let bestVisualCandidates = bestRecentVisualCandidates(from: visualMatches)
            primaryMatch = bestVisualCandidates.first ?? visualMatches.first
            let primaryID = primaryMatch?.snapshot.id
            alternatives = Array(visualMatches.filter { $0.snapshot.id != primaryID }.prefix(4))
        }

        guard let primaryMatch else { return nil }

        return SearchResult(
            item: item,
            primaryMatch: primaryMatch,
            contextStrip: library.contextStrip(around: primaryMatch.snapshot.id),
            alternativeMatches: alternatives
        )
    }

    private func buildVisualMatches(for item: TrackedItem, snapshots: [TimelineSnapshot]) -> [SearchMatch] {
        let referencePaths = item.referencePhotos.map(\.imagePath)
        guard !referencePaths.isEmpty else { return [] }

        var matches: [SearchMatch] = []
        for snapshot in snapshots where !snapshot.visibleItemIDs.contains(item.id) {
            let distances = referencePaths.compactMap { referencePath in
                try? similarityService.distance(
                    between: referencePath,
                    and: snapshot.imagePath,
                    imageLoader: store.loadImage(relativePath:)
                )
            }

            guard let bestDistance = distances.min() else { continue }
            matches.append(
                SearchMatch(
                    snapshot: snapshot,
                    evidence: .visualSimilarity(distance: bestDistance),
                    score: 1 / (1 + bestDistance)
                )
            )
        }

        return matches.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.snapshot.capturedAt > rhs.snapshot.capturedAt
            }
            return lhs.score > rhs.score
        }
    }

    private func bestRecentVisualCandidates(from matches: [SearchMatch]) -> [SearchMatch] {
        guard let bestScore = matches.first?.score else { return [] }
        let floor = bestScore * 0.92

        return matches
            .filter { $0.score >= floor }
            .sorted { lhs, rhs in
                lhs.snapshot.capturedAt > rhs.snapshot.capturedAt
            }
    }
}
