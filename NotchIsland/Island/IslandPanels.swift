import AppKit
import SwiftUI

extension NSWindow.Level {
    /// Über der Menüleiste und über Vollbild-Apps.
    static let island = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    static let islandHotspot = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
}

/// Randloses, nicht aktivierendes Panel, das auf allen Spaces und über Vollbild-Apps liegt.
class IslandBasePanel: NSPanel {
    init(contentRect: NSRect, level: NSWindow.Level) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Achtung: `isFloatingPanel` setzt das Level zurück, daher vor `level` setzen.
        isFloatingPanel = true
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
    }

    /// Fenster darf die Menüleiste überdecken.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeMain: Bool { false }
}

/// Das große Panel mit der SwiftUI-Island. Ignoriert Mausereignisse, solange es zugeklappt ist.
final class IslandPanel: IslandBasePanel {
    /// Nur für QuickLook kurzzeitig Key-Window werden, sonst nie Tastatur-Fokus stehlen.
    var allowsKey = false

    /// Datenquelle, solange QuickLook aus der Ablage heraus geöffnet ist.
    var previewController: QuickLookController?

    /// Solange ein Tab mit Eingabefeld (Timer) offen ist, darf das Panel Key-Window werden.
    var acceptsTextInput = false

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, level: .island)
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { allowsKey || acceptsTextInput }

    override var canBecomeMain: Bool { allowsKey }
}

/// Kleines, unsichtbares Panel direkt über der Notch: erkennt Hover, Klick und Drag-Hover.
final class HotspotPanel: IslandBasePanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, level: .islandHotspot)
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
}

/// NSHostingView, die schon den ersten Klick annimmt (die Island ist nie Key-Window).
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
