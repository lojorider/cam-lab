import AVFoundation
import AppKit
import Combine
import Foundation

@MainActor
final class TimeLapseViewModel: ObservableObject {
    @Published var settings = CaptureSettings()
    @Published var state: RecordingState = .idle
    @Published var framesCaptured: Int = 0
    @Published var recordingStartTime: Date?

    let cameraManager = CameraManager()

    private var captureTimer: Timer?
    private var framesDirectory: URL?

    // MARK: - Computed

    var estimatedVideoDuration: String {
        guard framesCaptured > 0 else { return "0.0s" }
        let seconds = Double(framesCaptured) / Double(settings.outputFPS.rawValue)
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = seconds - Double(mins * 60)
        return String(format: "%dm %.1fs", mins, secs)
    }

    var intervalText: String {
        String(format: "%.1fs", settings.captureInterval)
    }

    var elapsedTime: String {
        guard let start = recordingStartTime else { return "--:--" }
        let elapsed = Date().timeIntervalSince(start)
        let mins = Int(elapsed) / 60
        let secs = Int(elapsed) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - Recording

    func startRecording() {
        guard state == .idle else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeLab_\(timestamp)")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            state = .error("Failed to create frames directory: \(error.localizedDescription)")
            return
        }

        framesDirectory = tempDir
        framesCaptured = 0
        recordingStartTime = Date()
        state = .recording

        scheduleCapture()
    }

    func stopRecording() {
        captureTimer?.invalidate()
        captureTimer = nil

        guard let framesDir = framesDirectory, framesCaptured > 0 else {
            state = .idle
            return
        }

        exportVideo(from: framesDir)
    }

    private func scheduleCapture() {
        captureFrame()

        captureTimer = Timer.scheduledTimer(
            withTimeInterval: settings.captureInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureFrame()
            }
        }
    }

    private func captureFrame() {
        guard state.isRecording else { return }

        Task {
            do {
                let data = try await cameraManager.capturePhoto()
                guard let framesDir = framesDirectory else { return }

                let frameNumber = framesCaptured + 1
                let filename = String(format: "frame_%04d.jpg", frameNumber)
                let fileURL = framesDir.appendingPathComponent(filename)

                if let image = NSImage(data: data),
                   let jpegData = jpegData(from: image, quality: 0.95) {
                    try jpegData.write(to: fileURL)
                    framesCaptured = frameNumber
                }
            } catch {
                print("Capture error: \(error.localizedDescription)")
            }
        }
    }

    private func jpegData(from image: NSImage, quality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    // MARK: - Export

    private func exportVideo(from framesDir: URL) {
        state = .exporting(progress: 0)

        let outputURL = framesDir
            .deletingLastPathComponent()
            .appendingPathComponent("TimeLab_\(framesDir.lastPathComponent).mp4")
        let fps = settings.outputFPS.rawValue

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let url = try await VideoExporter.exportVideo(
                    framesDirectory: framesDir,
                    outputURL: outputURL,
                    fps: fps
                ) { progress in
                    Task { @MainActor [weak self] in
                        self?.state = .exporting(progress: progress)
                    }
                }

                await MainActor.run { [weak self] in
                    self?.state = .finished(url: url)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.state = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Save & Cleanup

    func saveVideo() {
        guard case .finished(let url) = state else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
                NSWorkspace.shared.activateFileViewerSelecting([destination])

                Task { @MainActor [weak self] in
                    self?.cleanupAndReset()
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.state = .error("Save failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func cleanupAndReset() {
        if let framesDir = framesDirectory {
            try? FileManager.default.removeItem(at: framesDir)

            let mp4 = framesDir
                .deletingLastPathComponent()
                .appendingPathComponent("TimeLab_\(framesDir.lastPathComponent).mp4")
            try? FileManager.default.removeItem(at: mp4)
        }

        framesDirectory = nil
        framesCaptured = 0
        recordingStartTime = nil
        state = .idle
    }

    func discardAndReset() {
        captureTimer?.invalidate()
        captureTimer = nil
        cleanupAndReset()
    }
}
