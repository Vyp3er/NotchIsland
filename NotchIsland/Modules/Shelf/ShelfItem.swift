import Foundation

/// Ein Element der Ablage.
struct ShelfItem: Identifiable, Codable, Equatable {
    enum Storage: String, Codable {
        /// Verweis auf eine vorhandene Datei (Standard, nichts wird kopiert).
        case reference
        /// Von NotchIsland angelegte Datei in Application Support (Bild aus dem Browser, Text, Link).
        case owned
    }

    let id: UUID
    var path: String
    var displayName: String
    var storage: Storage
    /// Lesezeichen, um eine per ⌘-Drag verschobene Datei wiederzufinden.
    var bookmark: Data?
    let addedAt: Date

    var url: URL { URL(fileURLWithPath: path) }

    var pathExtension: String { url.pathExtension }

    init(url: URL, storage: Storage) {
        id = UUID()
        path = url.path
        displayName = url.lastPathComponent
        self.storage = storage
        bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        addedAt = Date()
    }
}
