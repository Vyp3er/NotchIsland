import Foundation

/// Speicherorte in `~/Library/Application Support/NotchIsland`.
enum AppPaths {
    static var supportDirectory: URL {
        #if DEBUG
        // Für Tests: eigener Datenordner statt der echten Ablage/Zwischenablage.
        if let override = ProcessInfo.processInfo.environment["NOTCHISLAND_SUPPORT_DIR"] {
            return ensure(URL(fileURLWithPath: override, isDirectory: true))
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return ensure(base.appendingPathComponent("NotchIsland", isDirectory: true))
    }

    /// Temporäre Dateien für Ablage-Inhalte ohne eigene Datei (Bilder, Text, Links).
    static var shelfFilesDirectory: URL {
        ensure(supportDirectory.appendingPathComponent("Shelf", isDirectory: true))
    }

    static var clipboardImagesDirectory: URL {
        ensure(supportDirectory.appendingPathComponent("Clipboard", isDirectory: true))
    }

    static var shelfIndexFile: URL { supportDirectory.appendingPathComponent("shelf.json") }

    static var clipboardIndexFile: URL { supportDirectory.appendingPathComponent("clipboard.json") }

    static var timersFile: URL { supportDirectory.appendingPathComponent("timers.json") }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
}
