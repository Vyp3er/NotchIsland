import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// QuickLook-Vorschaubilder mit Speicher-Cache.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 300
    }

    /// Schon erzeugtes Vorschaubild (für Drag-Bilder, die synchron gebraucht werden).
    func cachedThumbnail(for url: URL, size: CGFloat) -> NSImage? {
        cache.object(forKey: key(for: url, size: size))
    }

    func thumbnail(for url: URL, size: CGFloat) async -> NSImage {
        let key = key(for: url, size: size)
        if let cached = cache.object(forKey: key) { return cached }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .all
        )
        let image: NSImage
        do {
            image = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        } catch {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Generisches Icon für einen Dateityp (z. B. wenn die Datei fehlt).
    func genericIcon(forPathExtension pathExtension: String) -> NSImage {
        let type = UTType(filenameExtension: pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    /// Der Schlüssel enthält das Änderungsdatum, geänderte Dateien bekommen so automatisch ein neues Bild.
    private func key(for url: URL, size: CGFloat) -> NSString {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(Int(size))|\(Int(modified))" as NSString
    }
}

extension NSImage {
    /// PNG-Daten des Bildes.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
