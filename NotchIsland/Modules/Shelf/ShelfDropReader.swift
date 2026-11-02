import AppKit
import UniformTypeIdentifiers

/// Pasteboard-Typen, die die Island als Drag-Ziel annimmt.
enum ShelfDropTypes {
    static let all: [NSPasteboard.PasteboardType] = {
        var types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .rtf, .tiff, .png]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        types += NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }
        var seen = Set<String>()
        return types.filter { seen.insert($0.rawValue).inserted }
    }()
}

/// Liest Drops aus dem Pasteboard: Dateien als Verweis, alles andere als eigene Datei in Application Support.
@MainActor
enum ShelfDropReader {
    enum Result {
        case references([URL])
        case owned(URL)
    }

    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "NotchIsland.FilePromises"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    static func hasContent(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(
            forClasses: [NSURL.self, NSFilePromiseReceiver.self, NSImage.self, NSString.self],
            options: nil
        )
    }

    /// Liest den Inhalt; `completion` kann bei File-Promises mehrfach und verzögert aufgerufen werden.
    @discardableResult
    static func read(_ pasteboard: NSPasteboard, completion: @escaping (Result) -> Void) -> Bool {
        // 1. Echte Dateien und Ordner aus Finder & Co. → nur Verweis speichern.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            completion(.references(urls.map(\.standardizedFileURL)))
            return true
        }

        // 2. Datei-Versprechen (Fotos, Mail-Anhänge, Bilder aus Browsern).
        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            for receiver in receivers {
                let directory = makeOwnedDirectory()
                receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: promiseQueue) { url, error in
                    DispatchQueue.main.async {
                        if let error {
                            Log.shelf.error("File promise failed: \(error.localizedDescription, privacy: .public)")
                            try? FileManager.default.removeItem(at: directory)
                        } else {
                            completion(.owned(url))
                        }
                    }
                }
            }
            return true
        }

        // 3. Bilddaten ohne Datei.
        if let url = writeImage(from: pasteboard) {
            completion(.owned(url))
            return true
        }

        // 4. Web-Links → .webloc
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let webURL = urls.first(where: { !$0.isFileURL }),
           let url = writeWebloc(webURL, title: pasteboard.string(forType: NSPasteboard.PasteboardType("public.url-name"))) {
            completion(.owned(url))
            return true
        }

        // 5. Markierter Text → .txt
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = writeText(text) {
            completion(.owned(url))
            return true
        }

        return false
    }

    // MARK: - Eigene Dateien

    private static func makeOwnedDirectory() -> URL {
        AppPaths.ensure(AppPaths.shelfFilesDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    private static func write(_ data: Data, named name: String) -> URL? {
        let url = makeOwnedDirectory().appendingPathComponent(sanitized(name))
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.shelf.error("Writing shelf file failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func writeImage(from pasteboard: NSPasteboard) -> URL? {
        // Originalformat bevorzugen (z. B. animierte GIFs), sonst als PNG speichern.
        let preferred: [(UTType, String)] = [(.png, "png"), (.jpeg, "jpg"), (.gif, "gif"), (.heic, "heic"), (.webP, "webp")]
        for (type, ext) in preferred {
            if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type.identifier)) {
                return write(data, named: "Bild \(timestamp()).\(ext)")
            }
        }
        guard let image = NSImage(pasteboard: pasteboard), let png = image.pngData() else { return nil }
        return write(png, named: "Bild \(timestamp()).png")
    }

    private static func writeWebloc(_ url: URL, title: String?) -> URL? {
        let plist: [String: String] = ["URL": url.absoluteString]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return nil
        }
        let base = title.flatMap { $0.isEmpty ? nil : $0 } ?? url.host ?? "Link"
        return write(data, named: "\(base).webloc")
    }

    private static func writeText(_ text: String) -> URL? {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        let base = firstLine.isEmpty ? "Text \(timestamp())" : String(firstLine.prefix(40))
        guard let data = text.data(using: .utf8) else { return nil }
        return write(data, named: "\(base).txt")
    }

    private static func sanitized(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Datei" : String(cleaned.prefix(80))
    }
}
