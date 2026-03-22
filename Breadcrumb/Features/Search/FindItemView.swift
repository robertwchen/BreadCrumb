import SwiftUI

struct FindItemView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var selectedItemID: UUID?
    @State private var result: SearchResult?
    @State private var isSearching = false

    var body: some View {
        List {
            if appModel.orderedItems.isEmpty {
                Section {
                    EmptyStateView(
                        title: "Nothing to search yet",
                        message: "Register at least one important item before asking Breadcrumb where it was last seen.",
                        systemImage: "magnifyingglass.circle"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                searchControls

                if isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Searching recent snapshots...")
                            Spacer()
                        }
                    }
                } else if let result {
                    Section("Last Likely Seen") {
                        primaryResultCard(result)
                    }

                    if result.contextStrip.count > 1 {
                        Section("Nearby Timeline Context") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(result.contextStrip, id: \.id) { snapshot in
                                        contextCard(snapshot, isPrimary: snapshot.id == result.primaryMatch.snapshot.id)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    if !result.alternativeMatches.isEmpty {
                        Section("Other Candidates") {
                            ForEach(result.alternativeMatches) { match in
                                alternativeMatchRow(match)
                            }
                        }
                    }
                } else {
                    Section {
                        EmptyStateView(
                            title: "Run a search",
                            message: "Pick a tracked item and Breadcrumb will look for the latest confirmed or visually similar snapshot.",
                            systemImage: "sparkle.magnifyingglass"
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Find Item")
        .onAppear {
            syncSelectedItem()
        }
        .onChange(of: appModel.orderedItems.map(\.id)) { _ in
            syncSelectedItem()
        }
    }

    private var searchControls: some View {
        Section("Query") {
            Picker("Tracked item", selection: Binding(
                get: { selectedItemID ?? appModel.orderedItems.first?.id ?? UUID() },
                set: { selectedItemID = $0 }
            )) {
                ForEach(appModel.orderedItems) { item in
                    Text(item.name).tag(item.id)
                }
            }

            Button {
                performSearch()
            } label: {
                Label("Find last seen moment", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
    }

    private func primaryResultCard(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            StoredImageView(relativePath: result.primaryMatch.snapshot.imagePath, cornerRadius: 24)
                .frame(height: 260)

            Text(result.primaryMatch.title)
                .font(.title3.bold())

            Text(result.primaryMatch.snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)

            Text(result.primaryMatch.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if result.primaryMatch.snapshot.hasContextNote {
                Text(result.primaryMatch.snapshot.contextNote)
                    .font(.body)
            }

            let contextText = contextSummary(for: result.contextStrip, primaryID: result.primaryMatch.snapshot.id)
            if !contextText.isEmpty {
                Text(contextText)
                    .font(.footnote)
                    .foregroundStyle(.indigo)
            }
        }
        .padding(.vertical, 8)
    }

    private func contextCard(_ snapshot: TimelineSnapshot, isPrimary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StoredImageView(relativePath: snapshot.imagePath, cornerRadius: 18)
                .frame(width: 160, height: 120)

            Text(snapshot.capturedAt.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.weight(.semibold))

            Text(snapshot.hasContextNote ? snapshot.contextNote : "No context note")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if isPrimary {
                Text("Matched frame")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.indigo)
            }
        }
        .frame(width: 160, alignment: .leading)
    }

    private func alternativeMatchRow(_ match: SearchMatch) -> some View {
        HStack(spacing: 14) {
            StoredImageView(relativePath: match.snapshot.imagePath, cornerRadius: 16)
                .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 6) {
                Text(match.snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)

                Text(match.title)
                    .font(.subheadline.weight(.medium))

                Text(match.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func contextSummary(for strip: [TimelineSnapshot], primaryID: UUID) -> String {
        let neighbors = strip.filter { $0.id != primaryID }
        guard !neighbors.isEmpty else { return "" }

        let snippets = neighbors.map { snapshot in
            snapshot.hasContextNote
                ? snapshot.contextNote
                : snapshot.capturedAt.formatted(date: .omitted, time: .shortened)
        }

        return "Nearby timeline: \(snippets.joined(separator: " | "))"
    }

    private func performSearch() {
        guard let selectedItemID, let item = appModel.orderedItems.first(where: { $0.id == selectedItemID }) else {
            return
        }

        isSearching = true
        result = nil

        Task {
            let searchResult = await appModel.search(for: item)
            result = searchResult
            isSearching = false
        }
    }

    private func syncSelectedItem() {
        if selectedItemID == nil {
            selectedItemID = appModel.orderedItems.first?.id
        } else if !appModel.orderedItems.contains(where: { $0.id == selectedItemID }) {
            selectedItemID = appModel.orderedItems.first?.id
        }
    }
}
