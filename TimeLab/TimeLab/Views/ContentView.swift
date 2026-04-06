import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TimeLapseViewModel()
    @State private var refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HSplitView {
            // MARK: - Preview Area
            ZStack {
                Color.black

                if viewModel.settings.showPreview {
                    CameraPreviewView(previewLayer: viewModel.cameraManager.previewLayer)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Preview Disabled")
                            .foregroundStyle(.secondary)
                    }
                }

                if !viewModel.cameraManager.isAuthorized {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Camera access required")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Grant access in System Settings → Privacy & Security → Camera")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }

                // Frame counter overlay
                if viewModel.state.isRecording {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                Text("\(viewModel.framesCaptured) frames")
                                    .font(.caption.monospacedDigit())
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(12)
                        }
                        Spacer()
                    }
                }
            }
            .frame(minWidth: 480, minHeight: 360)

            // MARK: - Sidebar
            ControlPanelView(viewModel: viewModel)
                .background(.ultraThinMaterial)
        }
        .onReceive(refreshTimer) { _ in
            if viewModel.state.isRecording {
                viewModel.objectWillChange.send()
            }
        }
        .onDisappear {
            viewModel.cameraManager.stopSession()
        }
    }
}
