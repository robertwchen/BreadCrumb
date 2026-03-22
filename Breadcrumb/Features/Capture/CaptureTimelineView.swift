import SwiftUI

struct CaptureTimelineView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var cameraController = CameraSessionController()

    @State private var sessionLabel = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                previewCard
                activeSessionCard
                recognizedCandidatesCard
                recentEventsCard
                pipelineCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Observe")
        .task {
            cameraController.requestAccessIfNeeded()
            cameraController.frameHandler = { frame in
                appModel.processRecordingFrame(frame)
            }
        }
        .onDisappear {
            cameraController.stopFrameDelivery()
            cameraController.stopSession()
            if appModel.activeSession != nil {
                Task {
                    try? await appModel.stopSession()
                }
            }
        }
        .alert("Observation Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Breadcrumb discovers object candidates while you observe. Fresh installs work immediately, and optional reference photos only strengthen identity confidence after an object matters.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("Optional session label", text: $sessionLabel)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                SessionMetricPill(title: "Detected", value: "\(appModel.counts.inboxCandidateCount)")
                SessionMetricPill(title: "Confirmed", value: "\(appModel.counts.trackedObjectCount)")
                SessionMetricPill(title: "Events", value: "\(appModel.counts.eventCount)")
            }

            Text("Promote important detections later from the Objects tab. Nothing needs to be uploaded before Observe becomes useful.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appModel.activeSession == nil ? "Live Camera" : "Observing Live")
                .font(.title3.weight(.semibold))

            if cameraController.authorizationStatus == .authorized {
                ZStack {
                    CameraPreviewContainer(session: cameraController.session)
                        .frame(height: 332)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    if !cameraController.isSessionReady {
                        ProgressView("Starting camera...")
                    }
                }
            } else {
                EmptyStateView(
                    title: "Camera access needed",
                    message: "Enable the camera to record object interactions.",
                    systemImage: "camera.fill"
                )
            }

            HStack {
                Label(
                    appModel.activeSession == nil ? "Idle" : "Recording",
                    systemImage: appModel.activeSession == nil ? "pause.circle" : "record.circle.fill"
                )
                .foregroundColor(appModel.activeSession == nil ? .secondary : .red)

                Spacer()

                if appModel.isAnalyzingFrame {
                    ProgressView()
                }
            }

            Button {
                toggleRecording()
            } label: {
                Label(appModel.activeSession == nil ? "Start Observe Session" : "Stop Observe Session", systemImage: appModel.activeSession == nil ? "play.fill" : "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(appModel.activeSession == nil ? .orange : .red)
            .disabled(
                cameraController.authorizationStatus != .authorized
                || !cameraController.isSessionReady
            )

            if appModel.counts.trackedObjectCount == 0 && appModel.counts.inboxCandidateCount == 0 {
                Text("Fresh install is okay. Detected candidates will appear here and in Objects as soon as the scene is stable enough.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if cameraController.authorizationStatus == .authorized && !cameraController.isSessionReady {
                Text("Waiting for the camera session to start.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var activeSessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session State")
                .font(.title3.weight(.semibold))

            if let session = appModel.activeSession {
                LabeledContent("Session", value: session.sessionLabel)
                LabeledContent("Started", value: session.startedAt.formatted(date: .omitted, time: .standard))
                LabeledContent("Frames analyzed", value: "\(session.analyzedFrameCount)")
                LabeledContent("Candidates seen", value: "\(session.localCandidateCount)")
                if cameraController.droppedFrameCount > 0 {
                    LabeledContent("Frames dropped", value: "\(cameraController.droppedFrameCount)")
                }
                if let backendStatusNote = session.backendStatusNote {
                    LabeledContent("Backend", value: backendStatusNote)
                }
            } else if let lastSession = appModel.lastCompletedSession {
                LabeledContent("Last session", value: lastSession.sessionLabel)
                LabeledContent("Ended", value: lastSession.endedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
                LabeledContent("Frames analyzed", value: "\(lastSession.analyzedFrameCount)")
            } else {
                Text("No recording sessions yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var recognizedCandidatesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Tracking")
                .font(.title3.weight(.semibold))

            if appModel.activeRecognitions.isEmpty {
                Text(appModel.activeSession == nil
                     ? "Start observing to discover candidates in view."
                     : "No candidates are stable enough yet. Hold the camera steady for a moment so tracking can lock on.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appModel.activeRecognitions) { status in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(status.title)
                                .font(.body.weight(.semibold))
                            Spacer()
                            Text(status.isPromoted ? "Confirmed" : "Auto-detected")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(status.isPromoted ? .green : .orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill((status.isPromoted ? Color.green : Color.orange).opacity(0.12))
                                )
                        }

                        Text(status.eventTitle)
                            .font(.subheadline.weight(.medium))

                        Text(status.contextSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        HStack {
                            Text(status.likelyLocation)
                                .lineLimit(1)
                            Spacer()
                            Text(confidenceSummary(for: status.confidence))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text(status.uncertaintySummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if status.id != appModel.activeRecognitions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var recentEventsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Timeline")
                .font(.title3.weight(.semibold))

            if appModel.recentSessionEvents.isEmpty {
                Text("Move an object into view or pick one up to build event history.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appModel.recentSessionEvents) { event in
                    EventRow(event: event)
                    if event.id != appModel.recentSessionEvents.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var pipelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How Observe Works")
                .font(.title3.weight(.semibold))

            Text("On-device only: Vision proposes likely objects from saliency and foreground masks, object tracking keeps continuity between proposal frames, hand pose contributes a hand-contact signal, and a local temporal model infers seen, resting on surface, picked up, in hand, possibly carried, reidentified, and put down. Optional reference photos only improve identity confidence.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if cameraController.droppedFrameCount > 0 {
                Text("Observe dropped \(cameraController.droppedFrameCount) frames during this session. Tracking remains resilient to short gaps, but longer gaps can still reduce certainty.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Hand-linked events remain approximate. Breadcrumb is strongest when the camera holds a steady view of the object before and after it moves.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func toggleRecording() {
        if appModel.activeSession == nil {
            Task {
                do {
                    try await appModel.startSession(label: sessionLabel)
                    cameraController.startFrameDelivery(interval: 0.18)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } else {
            Task {
                do {
                    cameraController.stopFrameDelivery()
                    try await appModel.stopSession()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func confidenceSummary(for confidence: Double) -> String {
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

private struct SessionMetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08), in: Capsule(style: .continuous))
    }
}
