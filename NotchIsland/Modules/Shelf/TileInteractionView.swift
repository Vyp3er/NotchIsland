import AppKit
import SwiftUI

/// AppKit-Ebene über einer Kachel: Klick/Auswahl, Doppelklick, Kontextmenü, Hover und
/// das Herausziehen mehrerer Dateien (SwiftUI-`onDrag` kann nur ein Element).
struct TileInteractionView: NSViewRepresentable {
    var toolTip: String?
    var onHover: (Bool) -> Void
    var onClick: (NSEvent.ModifierFlags) -> Void
    var onDoubleClick: () -> Void
    var onBeginDrag: (NSView, NSEvent) -> Void
    var makeMenu: () -> NSMenu?

    func makeNSView(context: Context) -> TileInteractionNSView {
        let view = TileInteractionNSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: TileInteractionNSView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: TileInteractionNSView) {
        view.toolTip = toolTip
        view.onHover = onHover
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.onBeginDrag = onBeginDrag
        view.makeMenu = makeMenu
    }
}

final class TileInteractionNSView: NSView {
    var onHover: (Bool) -> Void = { _ in }
    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}
    var onBeginDrag: (NSView, NSEvent) -> Void = { _, _ in }
    var makeMenu: () -> NSMenu? = { nil }

    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }

    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { onHover(false) }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
        if event.clickCount == 2 { onDoubleClick() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let start = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - start.locationInWindow.x
        let dy = event.locationInWindow.y - start.locationInWindow.y
        guard hypot(dx, dy) >= 4 else { return }
        didStartDrag = true
        onBeginDrag(self, start)
    }

    override func mouseUp(with event: NSEvent) {
        if !didStartDrag, event.clickCount == 1 {
            onClick(event.modifierFlags)
        }
        mouseDownEvent = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        makeMenu()
    }
}
