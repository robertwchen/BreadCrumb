import SwiftUI

struct ItemLibraryView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var isShowingRegisterSheet = false
    @State private var captureTargetObjectID: UUID?
    @State private var errorMessage: String?
    @State private var isShowingResetConfirmation = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Breadcrumb discovers object candidates while you observe.")
                        .font(.headline)

                    Text("Promote important detections into named objects when they matter. Optional reference photos can sharpen identity later, but they are never required to start.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        libraryMetric(title: "Detected", value: "\(appModel.counts.inboxCandidateCount)")
                        libraryMetric(title: "Confirmed", value: "\(appModel.counts.trackedObjectCount)")
                        libraryMetric(title: "Missing", value: "\(appModel.counts.possibleMissingCount)")
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }

            if !appModel.inboxCandidates.isEmpty {
                Section("Detected Candidates") {
                    ForEach(appModel.inboxCandidates) { summary in
                        NavigationLink {
                            CandidateDetailView(candidateID: summary.id)
                        } label: {
                            candidateRow(for: summary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                do {
                                    try appModel.dismissCandidate(candidateID: summary.id)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            } label: {
                                Label("Dismiss", systemImage: "trash")
                            }
                        }
                    }
                }
            } else {
                Section {
                    EmptyStateView(
                        title: "No detected candidates yet",
                        message: "Open Observe and hold the camera steady on a scene. Breadcrumb will auto-discover candidates and place them here.",
                        systemImage: "square.stack.3d.up"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            if appModel.objectStatusSummaries.isEmpty {
                Section {
                    EmptyStateView(
                        title: appModel.inboxCandidates.isEmpty ? "No confirmed objects yet" : "Promote a candidate to confirm it",
                        message: appModel.inboxCandidates.isEmpty
                            ? "You can name an object now or wait until Breadcrumb discovers it while you observe."
                            : "Detected candidates are ready. Promote one to create a named memory trail with optional reference photos later.",
                        systemImage: "shippingbox"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Confirmed Objects") {
                    ForEach(appModel.objectStatusSummaries) { summary in
                        NavigationLink {
                            ObjectDetailView(objectID: summary.objectID)
                        } label: {
                            objectRow(for: summary)
                        }
                    }
                }
            }

            Section("Local Memory Graph") {
                Text(appModel.backendConfigured
                     ? "The phone keeps a local memory graph first. A hosted refinement path can be layered in later for stronger identity work."
                     : "The phone is currently using the local automatic pipeline. Hosted refinement remains optional, and Observe works without it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    isShowingResetConfirmation = true
                } label: {
                    Label("Clear local memory data", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Objects")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingRegisterSheet = true
                } label: {
                    Label("New Object", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingRegisterSheet) {
            NavigationStack {
                RegisterItemView()
            }
            .presentationDetents([.large])
        }
        .sheet(item: Binding(
            get: { captureTargetObjectID.map(CaptureTarget.init(id:)) },
            set: { captureTargetObjectID = $0?.id }
        )) { target in
            CameraCaptureView(
                title: "Add Reference",
                subtitle: "Optional photos help future re-identification after Breadcrumb has already learned this object."
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
        .confirmationDialog(
            "Clear all Breadcrumb memory data?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Local Data", role: .destructive) {
                do {
                    try appModel.clearLibrary()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes candidates, objects, sessions, events, and evidence stored on this device.")
        }
    }

    private func libraryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func candidateRow(for summary: CandidateSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if let path = summary.latestEvidencePath {
                    StoredImageView(relativePath: path, cornerRadius: 16)
                        .frame(width: 78, height: 78)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(summary.title)
                            .font(.headline)

                        candidateBadge(title: "Auto-detected", color: .orange)

                        if summary.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(summary.lastEventTitle)
                        .font(.subheadline.weight(.medium))

                    Text(summary.lastState?.likelyLocation ?? summary.lastState?.lastContextSummary ?? "Still building context")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack {
                if let lastSeenAt = summary.lastSeenAt {
                    Text("Last seen \(lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Waiting for a stable sighting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                    Text(confidenceLabel(for: summary.lastState?.confidence ?? summary.clusterConfidence))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }

    private func objectRow(for summary: ObjectStatusSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if let path = summary.primaryReferenceImagePath ?? summary.latestEvidencePath {
                    StoredImageView(relativePath: path, cornerRadius: 16)
                        .frame(width: 80, height: 80)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(summary.displayName)
                            .font(.headline)

                        candidateBadge(title: "Confirmed", color: .green)

                        if summary.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if !summary.userNotes.isEmpty {
                        Text(summary.userNotes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text(summary.lastState?.lastEventType.title ?? "No events yet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.isPossiblyLost ? .red : .orange)

                    Text(summary.lastState?.likelyLocation ?? "No likely location yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack {
                if let lastSeenAt = summary.lastState?.lastSeenAt {
                    Text("Last seen \(lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No confirmed sightings yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    captureTargetObjectID = summary.objectID
                } label: {
                    Label("Add reference", systemImage: "camera")
                }
                .buttonStyle(.bordered)

                Button(summary.isPinned ? "Unpin" : "Pin") {
                    do {
                        try appModel.togglePinnedForObject(summary.objectID)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }

    private func candidateBadge(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
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

struct CandidateDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    let candidateID: UUID

    @State private var proposedName = ""
    @State private var notes = ""
    @State private var errorMessage: String?

    private var history: CandidateHistorySummary? {
        appModel.candidateHistory(for: candidateID)
    }

    var body: some View {
        List {
            if let history {
                Section {
                    candidateHeader(history.candidateSummary)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Last Known State") {
                    if let state = history.candidateSummary.lastState {
                        LabeledContent("Last event", value: state.lastEventType.title)
                        LabeledContent("Last seen", value: state.lastSeenAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Likely location", value: state.likelyLocation)
                        LabeledContent("Context", value: state.lastContextSummary)
                        LabeledContent("Identity confidence", value: confidenceLabel(for: state.confidence))
                    } else {
                        Text("Breadcrumb has not held a stable enough sighting to describe this candidate yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Promote This Candidate") {
                    Text("This candidate was auto-discovered while observing. Promote it when you want a named object memory. Reference photos can be added later and remain optional.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Object name", text: $proposedName)
                        .textInputAutocapitalization(.words)

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)

                    Button("Promote Candidate") {
                        promoteCandidate()
                    }
                    .disabled(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Actions") {
                    Button(history.candidateSummary.isPinned ? "Unpin Candidate" : "Pin Candidate") {
                        do {
                            try appModel.togglePinnedForCandidate(candidateID)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }

                    Button("Dismiss Candidate", role: .destructive) {
                        dismissCandidate()
                    }
                }

                if history.recentEvents.isEmpty {
                    Section {
                        EmptyStateView(
                            title: "No event history yet",
                            message: "Keep observing this object for a little longer to build a more reliable event trail.",
                            systemImage: "timeline.selection"
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Recent Timeline") {
                        ForEach(history.recentEvents) { event in
                            EventRow(event: event)
                        }
                    }
                }
            } else {
                Section {
                    EmptyStateView(
                        title: "Candidate not found",
                        message: "This candidate is no longer available in local memory.",
                        systemImage: "shippingbox"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(history?.candidateSummary.title ?? "Candidate")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard proposedName.isEmpty, let history else { return }
            if !history.candidateSummary.title.hasPrefix("Detected object ") {
                proposedName = history.candidateSummary.title
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

    private func candidateHeader(_ summary: CandidateSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                if let path = summary.latestEvidencePath {
                    StoredImageView(relativePath: path, cornerRadius: 20)
                        .frame(width: 96, height: 96)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(summary.title)
                            .font(.title3.bold())

                        Text("Auto")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.orange.opacity(0.12))
                            )
                    }

                    Text(summary.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(summary.lastState?.lastEventType.title ?? "Waiting for a stable event")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                Spacer()
            }

            Text("Auto-detected candidates are approximate identities. Promotion gives this one a stable name in memory; optional reference photos later can improve future re-identification.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func promoteCandidate() {
        do {
            try appModel.promoteCandidate(candidateID: candidateID, displayName: proposedName, notes: notes)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dismissCandidate() {
        do {
            try appModel.dismissCandidate(candidateID: candidateID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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

private struct CaptureTarget: Identifiable {
    let id: UUID
}
