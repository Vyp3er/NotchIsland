import AppKit

// Reiner AppKit-Start: kein Dock-Icon (LSUIElement), nur Menüleisten-Icon und Island.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
