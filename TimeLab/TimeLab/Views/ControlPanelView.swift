import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var viewModel: TimeLapseViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // MARK: - Camera Selection
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Camera")
                        .font(.headline)

                    if viewModel.cameraManager.availableCameras.isEmpty {
                        Text("No cameras found")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        Picker("", selection: Binding(
                            get: { viewModel.cameraManager.selectedCamera },
                            set: { viewModel.cameraManager.selectedCamera = $0 }
                        )) {
                            ForEach(viewModel.cameraManager.availableCameras) { cam in
                                Text(cam.name).tag(Optional(cam))
                            }
                        }
                        .labelsHidden()
                        .disabled(viewModel.state.isRecording)
                    }
                }
                .padding(4)
            }

            // MARK: - Capture Settings
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Capture Settings")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Snapshots / min")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(viewModel.settings.snapshotsPerMinute))")
                                .monospacedDigit()
                                .fontWeight(.medium)
                        }
                        Slider(
                            value: $viewModel.settings.snapshotsPerMinute,
                            in: 1...60,
                            step: 1
                        )
                        .disabled(viewModel.state.isRecording)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Output Frame Rate")
                            .foregroundStyle(.secondary)
                        Picker("", selection: $viewModel.settings.outputFPS) {
                            ForEach(OutputFPS.allCases) { fps in
                                Text(fps.label).tag(fps)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(viewModel.state.isRecording)
                    }

                    Toggle("Show Preview", isOn: $viewModel.settings.showPreview)
                }
                .padding(4)
            }

            // MARK: - Status Dashboard
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Status")
                        .font(.headline)

                    StatusRow(label: "Frames Captured", value: "\(viewModel.framesCaptured)")
                    StatusRow(label: "Interval", value: viewModel.intervalText)
                    StatusRow(label: "Est. Video Length", value: viewModel.estimatedVideoDuration)

                    if viewModel.state.isRecording {
                        StatusRow(label: "Elapsed", value: viewModel.elapsedTime)
                    }

                    if case .exporting(let progress) = viewModel.state {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Exporting...")
                                .foregroundStyle(.secondary)
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(4)
            }

            Spacer()

            // MARK: - Record Button
            recordButton
        }
        .padding()
        .frame(width: 280)
    }

    @ViewBuilder
    private var recordButton: some View {
        switch viewModel.state {
        case .idle:
            Button(action: viewModel.startRecording) {
                Label("Start Recording", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(!viewModel.cameraManager.isAuthorized)

        case .recording:
            Button(action: viewModel.stopRecording) {
                HStack(spacing: 8) {
                    PulsingDot()
                    Text("Stop Recording")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)

        case .exporting:
            Button(action: {}) {
                Label("Exporting...", systemImage: "film")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(true)

        case .finished:
            VStack(spacing: 8) {
                Button(action: viewModel.saveVideo) {
                    Label("Save Video", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)

                Button("Discard", role: .destructive, action: viewModel.discardAndReset)
                    .controlSize(.small)
            }

        case .error(let message):
            VStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)

                Button("Reset", action: viewModel.discardAndReset)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Supporting Views

private struct StatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.callout)
            Spacer()
            Text(value)
                .monospacedDigit()
                .fontWeight(.medium)
                .font(.callout)
        }
    }
}

private struct PulsingDot: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 8, height: 8)
            .opacity(isAnimating ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}
