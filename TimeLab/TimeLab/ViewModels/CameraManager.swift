import AVFoundation
import AppKit
import Combine

struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let device: AVCaptureDevice

    static func == (lhs: CameraDevice, rhs: CameraDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
final class CameraManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var lastCapturedImage: NSImage?
    @Published var availableCameras: [CameraDevice] = []
    @Published var selectedCamera: CameraDevice? {
        didSet {
            if let camera = selectedCamera, camera != oldValue {
                switchCamera(to: camera.device)
            }
        }
    }

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var photoContinuation: CheckedContinuation<Data, Error>?

    override init() {
        super.init()
        checkAuthorization()
    }

    // MARK: - Authorization

    private func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            discoverCameras()
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.isAuthorized = granted
                    if granted {
                        self?.discoverCameras()
                        self?.setupSession()
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }

    // MARK: - Camera Discovery

    private func discoverCameras() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )

        availableCameras = discoverySession.devices.map { device in
            CameraDevice(id: device.uniqueID, name: device.localizedName, device: device)
        }

        if selectedCamera == nil {
            selectedCamera = availableCameras.first
        }
    }

    // MARK: - Session Setup

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        let camera = selectedCamera?.device ?? AVCaptureDevice.default(for: .video)

        guard let camera,
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.previewLayer = layer

        Task.detached { [weak self] in
            self?.session.startRunning()
        }
    }

    private func switchCamera(to device: AVCaptureDevice) {
        session.beginConfiguration()

        // Remove existing input
        for input in session.inputs {
            session.removeInput(input)
        }

        // Add new input
        guard let newInput = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(newInput) else {
            session.commitConfiguration()
            return
        }

        session.addInput(newInput)
        session.commitConfiguration()
    }

    nonisolated func stopSession() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    // MARK: - Photo Capture

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: @preconcurrency AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            photoContinuation?.resume(throwing: error)
            photoContinuation = nil
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            photoContinuation?.resume(throwing: NSError(domain: "CameraManager", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get photo data"]))
            photoContinuation = nil
            return
        }

        self.lastCapturedImage = NSImage(data: data)
        photoContinuation?.resume(returning: data)
        photoContinuation = nil
    }
}
