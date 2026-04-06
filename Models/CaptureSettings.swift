import Foundation

enum RecordingState: Equatable {
    case idle
    case recording
    case exporting(progress: Double)
    case finished(url: URL)
    case error(String)

    var isRecording: Bool { self == .recording }

    var isExporting: Bool {
        if case .exporting = self { return true }
        return false
    }
}

enum OutputFPS: Int, CaseIterable, Identifiable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var label: String { "\(rawValue) FPS" }
}

struct CaptureSettings {
    var snapshotsPerMinute: Double = 10
    var outputFPS: OutputFPS = .fps30
    var showPreview: Bool = true

    /// Recording duration in minutes. 0 = unlimited (manual stop).
    var durationMinutes: Double = 0

    var captureInterval: TimeInterval {
        60.0 / snapshotsPerMinute
    }

    var hasDurationLimit: Bool {
        durationMinutes > 0
    }

    var durationSeconds: TimeInterval {
        durationMinutes * 60.0
    }
}
