import AppKit

/// NSMenuItem mit Closure statt Target/Action.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, systemImage: String? = nil, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        isEnabled = enabled
        if let systemImage {
            image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        }
    }

    required init(coder: NSCoder) {
        handler = {}
        super.init(coder: coder)
    }

    @objc private func fire() { handler() }
}
