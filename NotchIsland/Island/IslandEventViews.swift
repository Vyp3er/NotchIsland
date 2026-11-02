import AppKit

/// Callbacks für Drag-&-Drop-Ziele der Island.
@MainActor
struct DropHandlers {
    /// Wird bei Betreten und jeder Bewegung aufgerufen; Punkt in Fensterkoordinaten.
    var update: (NSDraggingInfo, NSPoint) -> NSDragOperation = { _, _ in [] }
    var exited: () -> Void = {}
    var perform: (NSDraggingInfo, NSPoint) -> Bool = { _, _ in false }
}

/// Inhalt des Island-Panels: enthält die SwiftUI-Ansicht und nimmt Drops entgegen.
final class IslandContainerView: NSView {
    var dropHandlers = DropHandlers()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes(ShelfDropTypes.all)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func embed(_ view: NSView) {
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHandlers.update(sender, sender.draggingLocation)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHandlers.update(sender, sender.draggingLocation)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropHandlers.exited()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dropHandlers.exited()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHandlers.perform(sender, sender.draggingLocation)
    }
}

/// Unsichtbare Fläche über der Notch. Erkennt Hover, Klick und Dateien, die darüber gezogen werden.
final class HotspotView: NSView {
    var onHoverChanged: (Bool) -> Void = { _ in }
    var onMouseMoved: () -> Void = {}
    var onClick: () -> Void = {}
    var dropHandlers = DropHandlers()

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Minimal deckend, damit der Window-Server Ereignisse nicht durchreicht (unsichtbar auf Schwarz).
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        registerForDraggedTypes(ShelfDropTypes.all)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseMoved(with event: NSEvent) { onMouseMoved() }

    override func mouseEntered(with event: NSEvent) { onHoverChanged(true) }

    override func mouseExited(with event: NSEvent) { onHoverChanged(false) }

    override func mouseDown(with event: NSEvent) { onClick() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHandlers.update(sender, sender.draggingLocation)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHandlers.update(sender, sender.draggingLocation)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropHandlers.exited()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHandlers.perform(sender, sender.draggingLocation)
    }
}
