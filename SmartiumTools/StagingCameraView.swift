import AVFoundation
import SwiftUI

#if os(iOS)
struct StagingCameraView: View {
    @Environment(\.scenePhase) private var scenePhase
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
        .task {
            await cameraManager.startPreview()
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                if newPhase == .active {
                    await cameraManager.startPreview()
                } else {
                    cameraManager.stopPreview()
                }
            }
        }
        .onDisappear {
            cameraManager.stopPreview()
        }
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
    let session = AVCaptureSession()

    private(set) var isRunning = false
    private(set) var statusMessage = "Preparando a câmera…"
    private var isConfigured = false

    func startPreview() async {
        let authorized = await requestCameraAccess()

        guard authorized else {
            statusMessage = "Autorize a câmera nas Configurações para visualizar o Staging."
            return
        }

        configureSession()

        if !session.isRunning {
            session.startRunning()
        }

        isRunning = session.isRunning

        if !isRunning {
            statusMessage = "Não foi possível iniciar a câmera."
        }
    }

    func stopPreview() {
        guard session.isRunning else { return }

        session.stopRunning()
        isRunning = session.isRunning
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

    private func configureSession() {
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
