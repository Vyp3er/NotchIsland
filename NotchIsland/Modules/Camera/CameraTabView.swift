import AVFoundation
import SwiftUI

/// Kamera-Tab: gespiegelte Live-Vorschau zum schnellen Check vor Meetings.
struct CameraTabView: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let width = min(proxy.size.width, height * 16 / 9)
            ZStack {
                switch camera.state {
                case .denied:
                    permissionHint
                case .unavailable:
                    message(icon: "video.slash.fill", title: "Keine Kamera gefunden", detail: "Die eingebaute Kamera ist nicht verfügbar.")
                default:
                    preview(width: width, height: height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func preview(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
            CameraPreview(session: camera.session, cornerRadius: 18)
                .opacity(camera.state == .running ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: camera.state)
            if camera.state != .running {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(camera.state == .requestingAccess ? "Warte auf Kamera-Freigabe …" : "Kamera startet …")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
        .frame(width: width, height: height)
        .overlay(alignment: .topLeading) {
            if camera.state == .running {
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Live")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .padding(10)
                .transition(.opacity)
            }
        }
    }

    private var permissionHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
            Text("Kein Zugriff auf die Kamera")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            Text("Erlaube NotchIsland den Kamerazugriff unter Datenschutz & Sicherheit → Kamera.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button("Systemeinstellungen öffnen") { CameraController.openPrivacySettings() }
                .buttonStyle(IslandPillButtonStyle())
                .padding(.top, 2)
        }
        .frame(maxWidth: 360)
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }
}

/// AVCaptureVideoPreviewLayer, horizontal gespiegelt wie ein Spiegel.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView(session: session, cornerRadius: cornerRadius)
    }

    func updateNSView(_ view: CameraPreviewNSView, context: Context) {
        view.applyMirroring()
    }
}

final class CameraPreviewNSView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession, cornerRadius: CGFloat) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
        applyMirroring()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
        applyMirroring()
    }

    func applyMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        if !connection.isVideoMirrored { connection.isVideoMirrored = true }
    }
}

/// Kleiner Pill-Button im Island-Stil.
struct IslandPillButtonStyle: ButtonStyle {
    /// Ohne Farbe: dezent grau; mit Farbe: gefüllt (Weiß mit schwarzer Schrift).
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(tint == .white ? Color.black : Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(background(pressed: configuration.isPressed)))
            .contentShape(Capsule())
    }

    private func background(pressed: Bool) -> Color {
        if let tint { return tint.opacity(pressed ? 0.7 : 0.9) }
        return Color.white.opacity(pressed ? 0.25 : 0.16)
    }
}
