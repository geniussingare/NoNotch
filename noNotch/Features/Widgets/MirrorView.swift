@preconcurrency import AVFoundation
import SwiftUI

/// Front camera preview, mirrored like a real mirror. The camera runs only
/// while this view is on screen.
struct MirrorView: View {
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                CameraPreview()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Design.fill)
                    .overlay {
                        Label("Allow Camera in Permissions", systemImage: "camera.fill")
                            .font(Design.text(12, .medium))
                            .foregroundStyle(Design.secondaryText)
                    }
            }
            IconButton(symbol: "chevron.left", size: 10, halo: 24, tint: .white, action: onBack)
                .background(Circle().fill(.black.opacity(0.4)))
                .padding(6)
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewView { CameraPreviewView() }
    func updateNSView(_ view: CameraPreviewView, context: Context) {}
    static func dismantleNSView(_ view: CameraPreviewView, coordinator: ()) { view.stop() }
}

final class CameraPreviewView: NSView {
    private let session = AVCaptureSession()
    private let previewLayer: AVCaptureVideoPreviewLayer

    override init(frame: NSRect) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: frame)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        previewLayer.connection?.isVideoMirrored = true
        layer?.addSublayer(previewLayer)

        session.sessionPreset = .medium
        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        // AVCaptureSession is documented as safe to start/stop off the main thread.
        nonisolated(unsafe) let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        // Connection exists only after the session has an input.
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    func stop() {
        nonisolated(unsafe) let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }
}
