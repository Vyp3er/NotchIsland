import AppKit
import Combine
import SwiftUI

/// "Now Playing" für die Island: MediaRemote-Adapter als Hauptquelle, AppleScript als Fallback.
@MainActor
final class NowPlayingService: ObservableObject {
    enum Backend: Equatable {
        case mediaRemote
        case appleScript
        case unavailable

        var title: String {
            switch self {
            case .mediaRemote: "MediaRemote-Adapter (alle Apps)"
            case .appleScript: "AppleScript (Musik & Spotify)"
            case .unavailable: "Nicht verfügbar"
            }
        }
    }

    @Published private(set) var info: NowPlayingInfo?
    @Published private(set) var backend: Backend = .unavailable
    /// Farbe aus dem Cover für Equalizer und Fortschrittsbalken.
    @Published private(set) var accentColor: Color = .white
    /// Steuert die Live-Aktivität (kurze Gnadenfrist beim Pausieren/Titelwechsel gegen Flackern).
    @Published private(set) var isActivelyPlaying = false

    private let settings: AppSettings
    private var adapter: MediaRemoteAdapterClient?
    private let script = AppleScriptNowPlayingClient()
    private var adapterInfo: NowPlayingInfo?
    private var scriptInfo: NowPlayingInfo?
    private var adapterFailed = false
    private var pauseGrace: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    /// Der Adapter hat auf dieser macOS-Version schon einmal Daten geliefert.
    private var adapterVerified: Bool {
        get { UserDefaults.standard.string(forKey: "mediaRemoteVerifiedOS") == Self.osVersion }
        set { UserDefaults.standard.set(newValue ? Self.osVersion : nil, forKey: "mediaRemoteVerifiedOS") }
    }

    private static let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

    init(settings: AppSettings) {
        self.settings = settings
        script.onUpdate = { [weak self] info in
            MainActor.assumeIsolated { self?.scriptInfo = info; self?.publish() }
        }
    }

    func start() {
        settings.$musicSource
            .removeDuplicates()
            .sink { [weak self] mode in
                DispatchQueue.main.async { self?.configure(mode) }
            }
            .store(in: &cancellables)
    }

    func stop() {
        adapter?.stop()
        script.stop()
    }

    // MARK: - Quellen

    private func configure(_ mode: MusicSourceMode) {
        adapter?.stop()
        adapter = nil
        script.stop()
        adapterInfo = nil
        scriptInfo = nil

        if mode == .automatic, !adapterFailed, let paths = MediaRemoteAdapterClient.bundledPaths() {
            let client = MediaRemoteAdapterClient(paths: paths)
            client.onUpdate = { [weak self] info in
                MainActor.assumeIsolated { self?.adapterUpdated(info) }
            }
            client.onFailure = { [weak self] in
                MainActor.assumeIsolated { self?.adapterDidFail() }
            }
            adapter = client
            backend = .mediaRemote
            client.start()
            // Noch nie bestätigt (z. B. nach einem macOS-Update)? Liefert der Adapter nach ein paar
            // Sekunden nichts, zusätzlich Musik/Spotify per AppleScript abfragen.
            if !adapterVerified {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    guard let self, self.adapter === client, self.adapterInfo == nil, !self.adapterVerified else { return }
                    self.script.start()
                }
            }
        } else {
            backend = .appleScript
            script.start()
        }
        publish()
    }

    private func adapterUpdated(_ info: NowPlayingInfo?) {
        adapterInfo = info
        if info != nil, !adapterVerified || script.isActive {
            adapterVerified = true
            script.stop()
            scriptInfo = nil
        }
        publish()
    }

    private func adapterDidFail() {
        Log.music.error("mediaremote-adapter unavailable, falling back to AppleScript")
        adapterFailed = true
        adapter = nil
        adapterInfo = nil
        backend = .appleScript
        script.start()
        publish()
    }

    private func publish() {
        let next = adapterInfo ?? scriptInfo
        if next != info {
            if next?.artworkID != info?.artworkID {
                accentColor = next?.artwork?.islandAccentColor().map(Color.init(nsColor:)) ?? .white
            }
            info = next
        }
        updatePlayingState(next?.isPlaying == true)
    }

    private func updatePlayingState(_ playing: Bool) {
        if playing {
            pauseGrace?.cancel()
            pauseGrace = nil
            if !isActivelyPlaying { isActivelyPlaying = true }
        } else if isActivelyPlaying, pauseGrace == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                pauseGrace = nil
                if info?.isPlaying != true { isActivelyPlaying = false }
            }
            pauseGrace = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        }
    }

    // MARK: - Steuerung

    func send(_ command: NowPlayingCommand) {
        switch info?.source {
        case .appleScript(let player):
            script.send(command, to: player)
        case .mediaRemote, .none:
            adapter?.send(command)
        }
    }

    func togglePlayPause() { send(.togglePlayPause) }
    func nextTrack() { send(.nextTrack) }
    func previousTrack() { send(.previousTrack) }

    func seek(to seconds: TimeInterval) {
        switch info?.source {
        case .appleScript(let player):
            script.seek(to: seconds, player: player)
        case .mediaRemote:
            adapter?.seek(to: seconds)
        case .none:
            break
        }
    }

    /// Öffnet die App, die gerade abspielt.
    func openSourceApp() {
        guard let bundleID = info?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    var sourceAppName: String? {
        guard let bundleID = info?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var sourceAppIcon: NSImage? {
        guard let bundleID = info?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
