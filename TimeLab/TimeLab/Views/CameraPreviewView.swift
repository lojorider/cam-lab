import AVFoundation
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?

    func makeNSView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        if let layer = previewLayer {
            view.setPreviewLayer(layer)
        }
        return view
    }

    func updateNSView(_ nsView: PreviewHostView, context: Context) {
        if let layer = previewLayer {
            nsView.setPreviewLayer(layer)
        }
        nsView.layoutPreview()
    }
}

final class PreviewHostView: NSView {
    private var currentPreviewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        guard layer !== currentPreviewLayer else { return }
        currentPreviewLayer?.removeFromSuperlayer()
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        self.layer?.addSublayer(layer)
        currentPreviewLayer = layer
    }

    func layoutPreview() {
        currentPreviewLayer?.frame = bounds
    }

    override func layout() {
        super.layout()
        currentPreviewLayer?.frame = bounds
    }
}
