import AppKit

/// Aktuell spielender Titel, unabhängig von der Quelle.
struct NowPlayingInfo: Equatable {
    enum Source: Equatable {
        case mediaRemote
        case appleScript(AppleScriptPlayer)
    }

    var title: String
    var artist: String
    var album: String
    /// Gesamtdauer in Sekunden.
    var duration: TimeInterval?
    /// Abgespielte Zeit zum Zeitpunkt `timestamp`.
    var elapsed: TimeInterval?
    var timestamp: Date?
    var playbackRate: Double
    var isPlaying: Bool
    /// App, die die Wiedergabe steuert (bei Web-Inhalten die übergeordnete Browser-App).
    var bundleIdentifier: String?
    var artwork: NSImage?
    /// Ändert sich nur, wenn sich das Cover ändert (für günstige Vergleiche).
    var artworkID: Int?
    var source: Source

    /// Hochgerechnete Position zum Zeitpunkt `date`.
    func elapsed(at date: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        var position = elapsed
        if isPlaying, let timestamp {
            position += date.timeIntervalSince(timestamp) * (playbackRate > 0 ? playbackRate : 1)
        }
        if let duration, duration > 0 { position = min(position, duration) }
        return max(0, position)
    }

    var trackKey: String { "\(title)|\(artist)|\(album)" }

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.duration == rhs.duration
            && lhs.elapsed == rhs.elapsed
            && lhs.timestamp == rhs.timestamp
            && lhs.playbackRate == rhs.playbackRate
            && lhs.isPlaying == rhs.isPlaying
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.artworkID == rhs.artworkID
            && lhs.source == rhs.source
    }
}

enum NowPlayingCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

extension NSImage {
    /// Durchschnittsfarbe, aufgehellt für die Darstellung auf Schwarz (Equalizer, Fortschritt).
    func islandAccentColor() -> NSColor? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let average = NSColor(
            deviceRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        return NSColor(
            hue: average.hueComponent,
            saturation: min(1, average.saturationComponent * 1.4),
            brightness: max(0.7, average.brightnessComponent),
            alpha: 1
        )
    }
}
