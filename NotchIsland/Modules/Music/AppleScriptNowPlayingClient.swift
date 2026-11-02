import AppKit

enum AppleScriptPlayer: String, CaseIterable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
    }
}

/// Fallback über AppleScript für Musik und Spotify.
/// Fragt nur laufende Apps ab (ein `tell` würde die App sonst starten).
final class AppleScriptNowPlayingClient {
    /// Neuer Zustand (nil = nichts spielt); wird auf dem Main-Thread aufgerufen.
    var onUpdate: (NowPlayingInfo?) -> Void = { _ in }

    private let queue = DispatchQueue(label: "NotchIsland.AppleScript")
    private var timer: Timer?
    private var artworkCache: (key: String, image: NSImage?)?
    /// Spieler, bei denen die Automation-Berechtigung verweigert wurde.
    private var deniedPlayers = Set<AppleScriptPlayer>()

    private static let separator = "|~|"

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var isActive: Bool { timer != nil }

    func send(_ command: NowPlayingCommand, to player: AppleScriptPlayer) {
        let verb: String
        switch command {
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .togglePlayPause: verb = "playpause"
        case .nextTrack: verb = "next track"
        case .previousTrack: verb = "previous track"
        }
        run("tell application id \"\(player.rawValue)\" to \(verb)") { _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.poll() }
    }

    func seek(to seconds: TimeInterval, player: AppleScriptPlayer) {
        let position = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), max(0, seconds))
        run("tell application id \"\(player.rawValue)\" to set player position to \(position)") { _ in }
    }

    // MARK: - Abfrage

    private func poll() {
        let running = AppleScriptPlayer.allCases.filter { $0.isRunning && !deniedPlayers.contains($0) }
        guard !running.isEmpty else {
            onUpdate(nil)
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            let results = running.compactMap(query)
            // Spielende Quelle bevorzugen, sonst die erste pausierte.
            let info = results.first(where: \.isPlaying) ?? results.first
            DispatchQueue.main.async { self.onUpdate(info) }
        }
    }

    private func query(_ player: AppleScriptPlayer) -> NowPlayingInfo? {
        let source = """
        tell application id "\(player.rawValue)"
            if player state is stopped then return ""
            set t to current track
            set s to "\(Self.separator)"
            return (player state as text) & s & (name of t) & s & (artist of t) & s & (album of t) & s & ((duration of t) as text) & s & (player position as text)
        end tell
        """
        guard let output = execute(source, player: player)?.stringValue, !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: Self.separator)
        guard parts.count == 6 else { return nil }

        func number(_ text: String) -> Double? {
            Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        }

        var duration = number(parts[4])
        // Spotify liefert die Dauer in Millisekunden.
        if player == .spotify, let value = duration { duration = value / 1000 }
        let title = parts[1]
        let artist = parts[2]
        let album = parts[3]
        let artwork = artwork(for: player, key: "\(player.rawValue)|\(title)|\(artist)|\(album)")

        return NowPlayingInfo(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: number(parts[5]),
            timestamp: Date(),
            playbackRate: 1,
            isPlaying: parts[0] == "playing",
            bundleIdentifier: player.rawValue,
            artwork: artwork,
            artworkID: artwork.map { ObjectIdentifier($0).hashValue },
            source: .appleScript(player)
        )
    }

    private func artwork(for player: AppleScriptPlayer, key: String) -> NSImage? {
        if let cache = artworkCache, cache.key == key { return cache.image }
        var image: NSImage?
        switch player {
        case .music:
            let source = "tell application id \"\(player.rawValue)\" to get raw data of artwork 1 of current track"
            if let data = execute(source, player: player)?.data, !data.isEmpty {
                image = NSImage(data: data)
            }
        case .spotify:
            let source = "tell application id \"\(player.rawValue)\" to get artwork url of current track"
            if let text = execute(source, player: player)?.stringValue,
               let url = URL(string: text), url.scheme == "https",
               let data = try? Data(contentsOf: url) {
                image = NSImage(data: data)
            }
        }
        artworkCache = (key, image)
        return image
    }

    // MARK: - Ausführung (läuft auf `queue`)

    private func execute(_ source: String, player: AppleScriptPlayer) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743: Automation nicht erlaubt → diesen Spieler nicht weiter fragen.
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
                DispatchQueue.main.async { self.deniedPlayers.insert(player) }
                Log.music.error("Automation for \(player.rawValue, privacy: .public) denied")
            }
            return nil
        }
        return result
    }

    private func run(_ source: String, completion: @escaping (NSAppleEventDescriptor?) -> Void) {
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            completion(error == nil ? result : nil)
        }
    }
}
