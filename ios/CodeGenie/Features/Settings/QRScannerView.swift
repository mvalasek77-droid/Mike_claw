import SwiftUI
import AVFoundation

/// SwiftUI wrapper around `AVCaptureMetadataOutput` for QR scanning.
///
/// Emits the decoded payload as a `String` via `onScan`. Calls
/// `onCancel` on tap of the close button. The first valid QR ends the
/// session — we expect the user to scan once, not stream.
struct QRScannerView: View {
    var onScan: (String) -> Void
    var onCancel: () -> Void

    @State private var authorization: AuthState = .checking
    @State private var lastError: String?

    enum AuthState { case checking, authorized, denied }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch authorization {
            case .checking:
                ProgressView().tint(LiquidGlass.primaryText)
            case .authorized:
                CameraPreview(
                    onScan: { code in
                        Haptics.success()
                        onScan(code)
                    },
                    onError: { lastError = $0 }
                )
                .ignoresSafeArea()
                overlay
            case .denied:
                deniedView
            }
        }
        .task { await requestAuthorization() }
        .onAppear { Haptics.tap(intensity: 0.4, sharpness: 0.5) }
    }

    // MARK: Subviews

    private var overlay: some View {
        VStack {
            HStack {
                Button { onCancel() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.85), .black.opacity(0.45))
                }
                .accessibilityLabel("Cancel scan")
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 16)

            Spacer()

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.8), lineWidth: 3)
                .frame(width: 260, height: 260)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(LiquidGlass.accent, lineWidth: 1.5)
                        .padding(6)
                )
                .shadow(color: .black.opacity(0.6), radius: 30)
                .accessibilityHidden(true)

            Spacer()

            VStack(spacing: 6) {
                Text("Aim at the pairing QR")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("Print or screenshot from the Mac terminal output.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                if let err = lastError {
                    Text(err)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.red.opacity(0.9))
                }
            }
            .padding(.bottom, 36)
        }
    }

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 50, weight: .bold))
                .foregroundStyle(LiquidGlass.warning)
            Text("Camera access denied")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Enable camera in Settings → CodeGenie to scan QR pairing codes. You can also paste the URL manually.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            PrimaryButton(title: "Close", systemImage: "xmark", style: .glass) { onCancel() }
                .frame(maxWidth: 200)
        }
    }

    // MARK: Plumbing

    private func requestAuthorization() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorization = granted ? .authorized : .denied
        default:
            authorization = .denied
        }
    }
}

// MARK: - Camera preview (UIKit bridge)

private struct CameraPreview: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> CameraController {
        CameraController(onScan: onScan, onError: onError)
    }

    func updateUIViewController(_ uiViewController: CameraController, context: Context) {}
}

private final class CameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onScan: (String) -> Void
    private let onError: (String) -> Void
    private var didScan = false

    init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onScan = onScan
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.forEach {
            if let preview = $0 as? AVCaptureVideoPreviewLayer { preview.frame = view.bounds }
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onError("No camera input")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            onError("Camera output unavailable")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didScan,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let payload = obj.stringValue else { return }
        didScan = true
        session.stopRunning()
        onScan(payload)
    }
}
