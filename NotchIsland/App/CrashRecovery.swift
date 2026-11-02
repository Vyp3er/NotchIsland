import Foundation

/// Startet NotchIsland nach einem Absturz automatisch neu.
///
/// Ein kleiner Wächter-Prozess (`/usr/bin/perl`) liest von einer Pipe, deren Schreibende nur
/// die App hält. Beim normalen Beenden schreibt die App "bye" und der Wächter endet still.
/// Stirbt die App unerwartet (Absturz, "Sofort beenden"), schließt das System die Pipe ohne
/// "bye" – dann öffnet der Wächter die App nach kurzer Pause erneut.
@MainActor
final class CrashRecovery {
    /// Startargument, mit dem der Wächter die App nach einem Absturz öffnet.
    static let restartArgument = "--restarted-after-crash"

    private static let watchdog = """
    my $app = shift @ARGV;
    my $line = <STDIN>;
    exit 0 if defined $line && $line =~ /^bye/;
    sleep 2;
    exec "/usr/bin/open", "-a", $app, "--args", "\(restartArgument)";
    """

    /// Höchstens so viele automatische Neustarts innerhalb von `crashLoopWindow`.
    private static let maxRestarts = 3
    private static let crashLoopWindow: TimeInterval = 10 * 60
    private static let historyKey = "crashRestartHistory"

    private var process: Process?
    private var pipe: Pipe?

    /// `false`, wenn die App in kurzer Zeit zu oft abgestürzt ist (Absturzschleife).
    let isAllowed: Bool

    init() {
        isAllowed = Self.recordLaunch()
    }

    var isArmed: Bool { pipe != nil }

    func setEnabled(_ enabled: Bool) {
        if enabled, isAllowed { arm() } else { disarm() }
    }

    private func arm() {
        guard pipe == nil else { return }
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.watchdog, "--", Bundle.main.bundlePath]
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            self.process = process
            self.pipe = pipe
            Log.app.info("Crash recovery armed")
        } catch {
            Log.app.error("Crash recovery could not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Beim normalen Beenden aufrufen: der Wächter endet, ohne neu zu starten.
    func disarm() {
        guard let pipe else { return }
        try? pipe.fileHandleForWriting.write(contentsOf: Data("bye\n".utf8))
        try? pipe.fileHandleForWriting.close()
        self.pipe = nil
        process = nil
    }

    /// Merkt sich Neustarts nach Abstürzen und erkennt Absturzschleifen.
    private static func recordLaunch() -> Bool {
        guard CommandLine.arguments.contains(restartArgument) else { return true }
        let now = Date().timeIntervalSince1970
        let history = (UserDefaults.standard.array(forKey: historyKey) as? [Double] ?? [])
            .filter { now - $0 < crashLoopWindow } + [now]
        UserDefaults.standard.set(history, forKey: historyKey)
        Log.app.error("Restarted after crash (\(history.count) in the last 10 minutes)")
        return history.count < maxRestarts
    }
}
