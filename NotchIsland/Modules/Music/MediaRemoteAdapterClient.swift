import AppKit

/// Liest "Now Playing" über das Open-Source-Projekt mediaremote-adapter.
///
/// Seit macOS 15.4 dürfen nur Apple-Prozesse das private MediaRemote-Framework nutzen. Der Adapter
/// lädt ein kleines Framework in `/usr/bin/perl` (ein Apple-Binary mit passender Berechtigung) und
/// streamt die Daten als JSON-Zeilen. Diese Klasse startet den Prozess, liest die Zeilen und
/// führt die Diff-Updates zu einem vollständigen Zustand zusammen.
final class MediaRemoteAdapterClient {
    struct Paths {
        let script: URL
        let framework: URL
    }

    /// Im App-Bundle enthaltenes Skript und Framework.
    static func bundledPaths() -> Paths? {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = Bundle.main.privateFrameworksURL else { return nil }
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework.path) else { return nil }
        return Paths(script: script, framework: framework)
    }

    /// Neuer Zustand (nil = nichts spielt); wird auf dem Main-Thread aufgerufen.
    var onUpdate: (NowPlayingInfo?) -> Void = { _ in }
    /// Der Adapter läuft wiederholt nicht (z. B. von einem macOS-Update blockiert).
    var onFailure: () -> Void = {}

    private let paths: Paths
    private let queue = DispatchQueue(label: "NotchIsland.MediaRemoteAdapter")
    private var process: Process?
    private var buffer = Data()
    private var state: [String: Any] = [:]
    private var lastArtworkBase64: String?
    private var lastArtwork: NSImage?
    private var isRunning = false
    private var recentFailures: [Date] = []

    init(paths: Paths) {
        self.paths = paths
    }

    deinit {
        process?.terminate()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        launch()
    }

    func stop() {
        isRunning = false
        process?.terminate()
        process = nil
    }

    func send(_ command: NowPlayingCommand) {
        runOnce(["send", String(command.rawValue)])
    }

    func seek(to seconds: TimeInterval) {
        runOnce(["seek", String(Int(max(0, seconds) * 1_000_000))])
    }

    // MARK: - Prozess

    /// Kleiner Wächter: startet den Adapter als Kindprozess und beendet ihn, sobald NotchIsland
    /// nicht mehr läuft (auch nach Absturz oder "Sofort beenden"), damit kein `perl` übrig bleibt.
    private static let watchdog = """
    use POSIX ":sys_wait_h";
    my $parent = getppid();
    my $pid = fork();
    exit 127 unless defined $pid;
    if ($pid == 0) { exec { "/usr/bin/perl" } "/usr/bin/perl", @ARGV or exit 127; }
    $SIG{TERM} = sub { kill "TERM", $pid; exit 0; };
    while (1) {
        sleep 1;
        if (getppid() != $parent) { kill "TERM", $pid; exit 0; }
        if (waitpid($pid, WNOHANG) == $pid) { exit($? >> 8); }
    }
    """

    private func launch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.watchdog, "--",
                             paths.script.path, paths.framework.path, "stream", "--debounce=80", "--micros"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] finished in
            output.fileHandleForReading.readabilityHandler = nil
            let status = finished.terminationStatus
            DispatchQueue.main.async { self?.processEnded(status: status) }
        }
        do {
            try process.run()
            self.process = process
            Log.music.info("mediaremote-adapter started")
        } catch {
            Log.music.error("mediaremote-adapter failed to start: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { self.processEnded(status: -1) }
        }
    }

    private func processEnded(status: Int32) {
        process = nil
        guard isRunning else { return }
        Log.music.error("mediaremote-adapter exited with status \(status)")
        let now = Date()
        recentFailures = recentFailures.filter { now.timeIntervalSince($0) < 60 } + [now]
        if recentFailures.count >= 3 {
            isRunning = false
            onFailure()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, isRunning, process == nil else { return }
                launch()
            }
        }
    }

    private func runOnce(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script.path, paths.framework.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.music.error("mediaremote-adapter command failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Parsen (läuft auf `queue`)

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line: Data(line))
        }
    }

    private func handle(line: Data) {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              (object["type"] as? String) == "data",
              let payload = object["payload"] as? [String: Any] else { return }

        if (object["diff"] as? Bool) == true {
            for (key, value) in payload {
                if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value }
            }
        } else {
            state = payload
        }

        let info = makeInfo(from: state)
        DispatchQueue.main.async { [weak self] in self?.onUpdate(info) }
    }

    private func makeInfo(from state: [String: Any]) -> NowPlayingInfo? {
        guard let title = state["title"] as? String, !title.isEmpty else { return nil }

        func number(_ key: String) -> Double? { (state[key] as? NSNumber)?.doubleValue }

        // Cover nur neu dekodieren, wenn es sich geändert hat.
        if let base64 = state["artworkData"] as? String {
            if base64 != lastArtworkBase64 {
                lastArtworkBase64 = base64
                lastArtwork = Data(base64Encoded: base64).flatMap(NSImage.init(data:))
            }
        } else {
            lastArtworkBase64 = nil
            lastArtwork = nil
        }
        let artworkID = lastArtwork == nil ? nil : lastArtworkBase64?.hashValue

        let parent = state["parentApplicationBundleIdentifier"] as? String
        return NowPlayingInfo(
            title: title,
            artist: state["artist"] as? String ?? "",
            album: state["album"] as? String ?? "",
            duration: number("durationMicros").map { $0 / 1_000_000 },
            elapsed: number("elapsedTimeMicros").map { $0 / 1_000_000 },
            timestamp: number("timestampEpochMicros").map { Date(timeIntervalSince1970: $0 / 1_000_000) },
            playbackRate: number("playbackRate") ?? 0,
            isPlaying: state["playing"] as? Bool ?? false,
            bundleIdentifier: (parent?.isEmpty == false ? parent : nil) ?? state["bundleIdentifier"] as? String,
            artwork: lastArtwork,
            artworkID: artworkID,
            source: .mediaRemote
        )
    }
}
