import AppKit

/// Kleines Menüleisten-Icon mit Einstellungen und Beenden.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let openSettings: () -> Void
    private let clearShelf: () -> Void

    init(openSettings: @escaping () -> Void, clearShelf: @escaping () -> Void) {
        self.openSettings = openSettings
        self.clearShelf = clearShelf
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotchIsland")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "NotchIsland"
        }

        let menu = NSMenu()
        menu.addItem(makeItem("Einstellungen …", action: #selector(settingsAction), key: ","))
        menu.addItem(makeItem("Ablage leeren", action: #selector(clearShelfAction), key: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("NotchIsland beenden", action: #selector(quitAction), key: "q"))
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func settingsAction() { openSettings() }
    @objc private func clearShelfAction() { clearShelf() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
