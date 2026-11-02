import Foundation

/// Ein Eintrag im Zwischenablage-Verlauf.
struct ClipboardItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text
        case link
        case image
        case files
    }

    let id: UUID
    var kind: Kind
    /// Text bzw. Link.
    var text: String?
    /// Dateiname des Bildes in `AppPaths.clipboardImagesDirectory`.
    var imageFileName: String?
    var filePaths: [String]?
    var isPinned: Bool
    var date: Date
    var sourceBundleID: String?
    /// Stabiler Fingerabdruck zum Erkennen doppelter Einträge.
    var fingerprint: String

    var imageURL: URL? {
        imageFileName.map { AppPaths.clipboardImagesDirectory.appendingPathComponent($0) }
    }

    var fileURLs: [URL] {
        (filePaths ?? []).map { URL(fileURLWithPath: $0) }
    }

    var linkURL: URL? {
        guard kind == .link, let text else { return nil }
        return URL(string: text)
    }

    /// Kurzer Vorschautext.
    var previewText: String {
        switch kind {
        case .text, .link:
            return text ?? ""
        case .image:
            return "Bild"
        case .files:
            let names = fileURLs.map(\.lastPathComponent)
            return names.count > 1 ? "\(names.count) Dateien: " + names.joined(separator: ", ") : names.first ?? "Datei"
        }
    }
}
