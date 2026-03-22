import SwiftUI

struct FindItemView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List {
            Section {
                statusOverview
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Text("Memory is the retrieval surface: what was recently handled, what may be missing, and the last known context Breadcrumb can defend with evidence.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            if appModel.objectStatusSummaries.isEmpty {
                Section {
                    EmptyStateView(
                        title: appModel.inboxCandidates.isEmpty ? "No confirmed memories yet" : "Candidates are ready to promote",
                        message: appModel.inboxCandidates.isEmpty
                            ? "Observe to discover candidates, then promote the important ones from Objects to create named memories here."
                            : "Breadcrumb has already detected candidates. Promote one from Objects to start a named memory trail.",
                        systemImage: "brain.head.profile"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                if !appModel.possiblyLostObjects.isEmpty {
                    Section("Possibly Carried") {
                        ForEach(appModel.possiblyLostObjects) { summary in
                            NavigationLink {
                                ObjectDetailView(objectID: summary.objectID)
                            } label: {
                                StatusCard(summary: summary)
                            }
                        }
                    }
                }

                if !appModel.recentlyHandledObjects.isEmpty {
                    Section("Recently Handled") {
                        ForEach(appModel.recentlyHandledObjects) { summary in
                            NavigationLink {
                                ObjectDetailView(objectID: summary.objectID)
                            } label: {
                                StatusCard(summary: summary)
                            }
                        }
                    }
                }

                Section("All Object Memories") {
                    ForEach(appModel.objectStatusSummaries) { summary in
                        NavigationLink {
                            ObjectDetailView(objectID: summary.objectID)
                        } label: {
                            StatusCard(summary: summary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Memory")
    }

    private var statusOverview: some View {
        HStack(spacing: 12) {
            StatusMetricCard(
                title: "Objects",
                value: "\(appModel.counts.trackedObjectCount)",
                detail: "confirmed"
            )
            StatusMetricCard(
                title: "Handled",
                value: "\(appModel.counts.recentlyHandledCount)",
                detail: "recent"
            )
            StatusMetricCard(
                title: "Missing",
                value: "\(appModel.counts.possibleMissingCount)",
                detail: "possible"
            )
        }
        .padding(.vertical, 8)
    }
}

private struct StatusMetricCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct StatusCard: View {
    let summary: ObjectStatusSummary

    var body: some View {
        HStack(spacing: 14) {
            if let path = summary.primaryReferenceImagePath ?? summary.latestEvidencePath {
                StoredImageView(relativePath: path, cornerRadius: 16)
                    .frame(width: 72, height: 72)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(summary.displayName)
                        .font(.headline)
                    Spacer(minLength: 12)
                    statusBadge
                }

                Text(summary.lastState?.lastEventType.title ?? "No timeline yet")
                    .font(.subheadline.weight(.medium))

                if let state = summary.lastState {
                    Text(state.lastSeenAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(state.likelyLocation)
                        .font(.caption)
                        .foregroundStyle(summary.isPossiblyLost ? .red : .orange)
                        .lineLimit(2)
                } else {
                    Text("No observation history yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lastHandledAt = summary.lastHandledAt {
                    Text("Handled \(lastHandledAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(summary.isPossiblyLost ? "Possibly carried" : "Confirmed")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(summary.isPossiblyLost ? .red : .green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill((summary.isPossiblyLost ? Color.red : Color.green).opacity(0.12))
            )
    }
}

struct ObjectDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    let objectID: UUID

    @State private var captureTargetObjectID: UUID?
    @State private var errorMessage: String?

    private var history: ObjectHistorySummary? {
        appModel.history(for: objectID)
    }

    var body: some View {
        List {
            if let history {
                Section {
                    objectHeader(history.objectSummary)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Last Known State") {
                    if let state = history.objectSummary.lastState {
                        LabeledContent("Last event", value: state.lastEventType.title)
                        LabeledContent("Last seen", value: state.lastSeenAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Likely location", value: state.likelyLocation)
                        LabeledContent("Context", value: state.lastContextSummary)
                        LabeledContent("State confidence", value: "\(Int(state.confidence * 100))%")
                        if let pickup = state.lastPickupAt {
                            LabeledContent("Last pickup", value: pickup.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let putDown = state.lastPutDownAt {
                            LabeledContent("Last put down", value: putDown.formatted(date: .abbreviated, time: .shortened))
                        }
                    } else {
                        Text("No memory state yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Reasoning") {
                    Text(history.objectSummary.isPossiblyLost
                         ? "Breadcrumb only marks this object as possibly carried when it left view after hand-linked motion. That is still a heuristic inference, not a guarantee."
                         : "Breadcrumb currently has a defended last-known state for this object based on recent observations and event inference.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Actions") {
                    Button("Add Optional Reference Photo") {
                        captureTargetObjectID = objectID
                    }
                    .foregroundStyle(.orange)

                    Button(history.objectSummary.isPinned ? "Unpin Object" : "Pin Object") {
                        do {
                            try appModel.togglePinnedForObject(objectID)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }

                if !history.interactions.isEmpty {
                    Section("Hand Interaction Timeline") {
                        ForEach(history.interactions) { interaction in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Picked up \(interaction.pickupTimestamp.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.body.weight(.medium))
                                Text(interaction.putDownTimestamp?.formatted(date: .abbreviated, time: .shortened) ?? "Put-down not observed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let duration = interaction.duration {
                                    Text("Carried for \(Duration.seconds(duration).formatted(.units(width: .abbreviated, maximumUnitCount: 2)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(interaction.contextSummary)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                if !history.recentEvents.isEmpty {
                    Section("Recent Timeline") {
                        ForEach(history.recentEvents) { event in
                            EventRow(event: event)
                        }
                    }
                }
            } else {
                Section {
                    EmptyStateView(
                        title: "Object not found",
                        message: "This object is no longer available in local memory.",
                        systemImage: "shippingbox"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(history?.objectSummary.displayName ?? "Object")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { captureTargetObjectID.map(ReferenceTarget.init(id:)) },
            set: { captureTargetObjectID = $0?.id }
        )) { target in
            CameraCaptureView(
                title: "Reference Capture",
                subtitle: "Optional photos can make future re-identification stronger."
            ) { image in
                do {
                    try appModel.addReferenceImage(image, to: target.id)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("Update Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func objectHeader(_ summary: ObjectStatusSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                if let referencePath = summary.primaryReferenceImagePath ?? summary.latestEvidencePath {
                    StoredImageView(relativePath: referencePath, cornerRadius: 20)
                        .frame(width: 92, height: 92)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(summary.displayName)
                        .font(.title3.bold())

                    if !summary.userNotes.isEmpty {
                        Text(summary.userNotes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(summary.isPossiblyLost ? "Possibly carried" : "User-confirmed memory")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.isPossiblyLost ? .red : .green)
                }

                Spacer()
            }

            if let lastSeenThumbnail = summary.lastState?.lastThumbnailPath {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last defended evidence")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    StoredImageView(relativePath: lastSeenThumbnail, cornerRadius: 18)
                        .frame(height: 180)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct EventRow: View {
    @EnvironmentObject private var appModel: AppModel
    let event: EventSnapshot

    var body: some View {
        HStack(spacing: 12) {
            if let path = event.evidencePath {
                StoredImageView(relativePath: path, cornerRadius: 14)
                    .frame(width: 64, height: 64)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(appModel.displayTitle(for: event.candidateID, objectID: event.trackedObjectID))
                    .font(.body.weight(.semibold))
                HStack {
                    Text(event.eventType.title)
                        .font(.subheadline)
                    Spacer()
                    Text(confidenceLabel(for: event.confidence))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let location = event.likelyLocation ?? event.contextLabel {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !event.note.isEmpty {
                    Text(event.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(event.eventType.isHandlingEvent
                     ? "Auto inference from tracking + hand evidence"
                     : "Observation-backed timeline event")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func confidenceLabel(for confidence: Double) -> String {
        switch confidence {
        case 0.82...:
            return "High \(Int(confidence * 100))%"
        case 0.64...:
            return "Moderate \(Int(confidence * 100))%"
        default:
            return "Tentative \(Int(confidence * 100))%"
        }
    }
}

private struct ReferenceTarget: Identifiable {
    let id: UUID
}
