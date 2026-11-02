import AppKit
import SwiftUI

/// Einstellungsfenster, geöffnet über das Menüleisten-Icon oder das Zahnrad in der Island.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var window: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView().withAppEnvironment(environment))
        let window = NSWindow(contentViewController: hosting)
        window.title = "NotchIsland"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 520, height: 600))
        window.center()
        return window
    }
}
