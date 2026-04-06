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
    @Published var savedMessage: String?

    let cameraManager = CameraManager()

    private var captureTimer: Timer?
    private var durationTimer: Timer?
    private var framesDirectory: URL?
    private var cancellables = Set<AnyCancellable>()

    private static let lastSaveFolderKey = "CamLab_lastSaveFolder"

    /// The folder where videos are auto-saved.
    var saveDirectory: URL {
        if let saved = UserDefaults.standard.string(forKey: Self.lastSaveFolderKey) {
            let url = URL(fileURLWithPath: saved)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        // Default: ~/Movies
        return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
    }

    init() {
        cameraManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        cleanupOrphanedSessions()

        // Ensure default save directory exists
        try? FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
    }

    /// Remove leftover CamLab_* folders/mp4s in tmp from previous crashed sessions
    private func cleanupOrphanedSessions() {
        let tmpDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        ) else { return }

        for item in contents where item.lastPathComponent.hasPrefix("CamLab_") {
            try? FileManager.default.removeItem(at: item)
        }
    }

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

    var remainingTime: String? {
        guard settings.hasDurationLimit, let start = recordingStartTime else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(0, settings.durationSeconds - elapsed)
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var saveDirectoryName: String {
        saveDirectory.lastPathComponent
    }

    // MARK: - Save Directory

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select Folder"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            UserDefaults.standard.set(url.path, forKey: Self.lastSaveFolderKey)
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard state == .idle else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CamLab_\(timestamp)")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            state = .error("Failed to create frames directory: \(error.localizedDescription)")
            return
        }

        framesDirectory = tempDir
        framesCaptured = 0
        recordingStartTime = Date()
        savedMessage = nil
        state = .recording

        scheduleCapture()
        scheduleDurationTimer()
    }

    func stopRecording() {
        captureTimer?.invalidate()
        captureTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil

        guard let framesDir = framesDirectory, framesCaptured > 0 else {
            state = .idle
            return
        }

        exportVideo(from: framesDir, autoSave: settings.hasDurationLimit)
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

    private func scheduleDurationTimer() {
        guard settings.hasDurationLimit else { return }

        durationTimer = Timer.scheduledTimer(
            withTimeInterval: settings.durationSeconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopRecording()
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

    private func exportVideo(from framesDir: URL, autoSave: Bool) {
        state = .exporting(progress: 0)

        let outputURL = framesDir
            .deletingLastPathComponent()
            .appendingPathComponent("CamLab_\(framesDir.lastPathComponent).mp4")
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
                    if autoSave {
                        self?.autoSaveVideo(tempURL: url)
                    } else {
                        self?.state = .finished(url: url)
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.state = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Auto Save

    private func autoSaveVideo(tempURL: URL) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "CamLab_\(dateFormatter.string(from: Date())).mp4"
        let destination = saveDirectory.appendingPathComponent(filename)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: tempURL, to: destination)
            savedMessage = "Saved to \(saveDirectory.lastPathComponent)/\(filename)"
            cleanupAndReset()
        } catch {
            state = .error("Auto-save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Manual Save & Cleanup

    func saveVideo() {
        guard case .finished(let url) = state else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true
        panel.directoryURL = saveDirectory

        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }

            // Remember the chosen folder
            let folder = destination.deletingLastPathComponent().path
            UserDefaults.standard.set(folder, forKey: Self.lastSaveFolderKey)

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
                .appendingPathComponent("CamLab_\(framesDir.lastPathComponent).mp4")
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
        durationTimer?.invalidate()
        durationTimer = nil
        savedMessage = nil
        cleanupAndReset()
    }
}
