import SwiftUI

struct SessionHistoryView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List {
            Section {
                Text("Sessions are the durable observation windows Breadcrumb uses to build its memory graph. Each session accumulates automatic candidate sightings, event inference, and evidence thumbnails.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            Section {
                Text("Each session records how detected and confirmed objects moved through time so you can recover last-known context later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            if appModel.sessions.isEmpty {
                Section {
                    EmptyStateView(
                        title: "No sessions yet",
                        message: "Start Observe mode to record your first object-memory session.",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Session History") {
                    ForEach(appModel.sessions) { session in
                        NavigationLink {
                            SnapshotReviewView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(session.sessionLabel)
                                    .font(.body.weight(.medium))
                                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(appModel.sessionEvents(for: session.id).count) events • \(session.localCandidateCount) candidates • \(session.analyzedFrameCount) frames")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sessions")
    }
}

struct SnapshotReviewView: View {
    @EnvironmentObject private var appModel: AppModel

    let session: SessionSnapshot

    private var events: [EventSnapshot] {
        appModel.sessionEvents(for: session.id)
    }

    private var candidateIDs: [UUID] {
        Array(Set(events.map(\.candidateID)))
    }

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Label", value: session.sessionLabel)
                LabeledContent("Started", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Ended", value: session.endedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Still active")
                LabeledContent("Frames analyzed", value: "\(session.analyzedFrameCount)")
                LabeledContent("Candidates seen", value: "\(session.localCandidateCount)")
                LabeledContent("Events inferred", value: "\(events.count)")
                if let backendStatusNote = session.backendStatusNote {
                    LabeledContent("Backend", value: backendStatusNote)
                }
            }

            if !candidateIDs.isEmpty {
                Section("Objects Seen") {
                    ForEach(candidateIDs, id: \.self) { candidateID in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title(for: candidateID))
                                .font(.body.weight(.medium))
                            Text("\(events.filter { $0.candidateID == candidateID }.count) events")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let lastEvent = events.first(where: { $0.candidateID == candidateID }) {
                                Text("\(lastEvent.eventType.title) • \(lastEvent.likelyLocation ?? lastEvent.contextLabel ?? "Location not stable yet")")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }

            if events.isEmpty {
                Section {
                    EmptyStateView(
                        title: "No events for this session",
                        message: "This session did not produce durable object interaction events.",
                        systemImage: "timeline.selection"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Interaction Timeline") {
                    ForEach(events) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func title(for candidateID: UUID) -> String {
        if let candidateSummary = appModel.candidateSummary(for: candidateID) {
            return candidateSummary.title
        }
        return "Object \(candidateID.uuidString.prefix(4))"
    }
}
