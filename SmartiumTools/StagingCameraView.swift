import AVFoundation
import SwiftUI

#if os(iOS)
struct StagingCameraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.stIsActiveTab) private var isActiveTab
    @State private var cameraManager = CameraPreviewManager()

    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.session)
                .clipShape(RoundedRectangle(cornerRadius: StRadius.card, style: .continuous))

            if !cameraManager.isRunning {
                StagingPlaceholder(
                    title: cameraManager.statusMessage,
                    message: "O preview da câmera traseira ocupa este painel inteiro."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .stBorderBeam(.fx, cornerRadius: StRadius.card)
        // v0.9.2: the tab stays loaded while hidden, so the session follows
        // the tab's visibility and the scene phase, not onAppear.
        .task(id: shouldRun) {
            if shouldRun {
                await cameraManager.startPreview()
            } else {
                cameraManager.stopPreview()
            }
        }
        .onDisappear {
            cameraManager.stopPreview()
        }
    }

    private var shouldRun: Bool {
        isActiveTab && scenePhase == .active
    }
}
#endif

#if os(iOS)
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        CameraPreviewView(session: session)
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {}
}

private final class CameraPreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

@Observable
private final class CameraPreviewManager {
    @ObservationIgnored private let controller = CameraSessionController()

    var session: AVCaptureSession { controller.session }

    private(set) var isRunning = false
    private(set) var statusMessage = "Preparando a câmera…"
    /// Cleared by `stopPreview()` so a start still awaiting authorization doesn't
    /// turn the camera back on after the view went away.
    private var wantsPreview = false

    func startPreview() async {
        wantsPreview = true
        let authorized = await requestCameraAccess()

        guard authorized else {
            statusMessage = "Autorize a câmera nas Configurações para visualizar o Staging."
            return
        }
        guard wantsPreview else { return }

        let running = await controller.start()
        guard wantsPreview else { return }

        isRunning = running

        if !running {
            statusMessage = "Não foi possível iniciar a câmera."
        }
    }

    func stopPreview() {
        wantsPreview = false
        isRunning = false
        controller.stop()
    }

    private func requestCameraAccess() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

/// Owns the capture session and runs every configuration/start/stop call on a
/// serial queue: `startRunning()` blocks until the camera is up, so it must stay
/// off the main thread. The serial queue also keeps start/stop in call order.
nonisolated private final class CameraSessionController: @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "dev.smartium.tools.camera-session")
    /// Only read or written on `queue`.
    private var isConfigured = false

    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                self.configureIfNeeded()

                if !self.session.isRunning {
                    self.session.startRunning()
                }

                continuation.resume(returning: self.session.isRunning)
            }
        }
    }

    func stop() {
        queue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        if let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ), let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
        }

        session.commitConfiguration()
        isConfigured = true
    }
}
#endif
