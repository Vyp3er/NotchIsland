@preconcurrency import AVFoundation
import AppKit

/// FaceTime-Kamera für den Spiegel-Tab. Läuft nur, solange der Tab sichtbar ist.
@MainActor
final class CameraController: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingAccess
        case starting
        case running
        case denied
        case unavailable
    }

    @Published private(set) var state: State = .idle

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "NotchIsland.Camera")
    private var isConfigured = false
    private var wantsActive = false

    /// Wird beim Öffnen/Schließen des Tabs bzw. der Island aufgerufen.
    func setActive(_ active: Bool) {
        guard active != wantsActive else { return }
        wantsActive = active
        if active { activate() } else { deactivate() }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private func activate() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            // Berechtigung erst anfragen, wenn der Kamera-Tab wirklich geöffnet wird.
            state = .requestingAccess
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !granted {
                        self.state = .denied
                    } else if self.wantsActive {
                        self.startSession()
                    } else {
                        self.state = .idle
                    }
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    private func startSession() {
        state = .starting
        let session = session
        let needsConfiguration = !isConfigured
        sessionQueue.async { [weak self] in
            if needsConfiguration {
                guard Self.configure(session) else {
                    DispatchQueue.main.async { self?.state = .unavailable }
                    return
                }
            }
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isConfigured = true
                if self.wantsActive {
                    self.state = .running
                } else {
                    // Tab wurde inzwischen geschlossen: sofort wieder freigeben.
                    self.deactivate()
                }
            }
        }
    }

    private func deactivate() {
        let session = session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
        if state == .running || state == .starting { state = .idle }
    }

    /// Bevorzugt die eingebaute FaceTime-Kamera vor Continuity- und externen Kameras.
    nonisolated private static func preferredDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first ?? AVCaptureDevice.default(for: .video)
    }

    nonisolated private static func configure(_ session: AVCaptureSession) -> Bool {
        guard let device = preferredDevice(),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        return true
    }
}
