#if DEBUG
import AppKit
import SwiftUI

/// Nur Debug-Builds: rendert die Island-Zustände als PNG, um das Layout ohne Bildschirm zu prüfen.
///
///     NOTCHISLAND_SNAPSHOT_DIR=/pfad NOTCHISLAND_SUPPORT_DIR=/tmp/daten NotchIsland.app/Contents/MacOS/NotchIsland
@MainActor
enum DebugSnapshots {
    static var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["NOTCHISLAND_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func run(environment: AppEnvironment, to directory: URL) {
        environment.prepareDebugSnapshot()
        Task { @MainActor in
            // Etwas warten, damit Musik-, Kalender- und Zwischenablage-Daten ankommen.
            try? await Task.sleep(for: .seconds(3))
            await render(environment: environment, to: directory)
            NSApp.terminate(nil)
        }
    }

    private static func render(environment: AppEnvironment, to directory: URL) async {
        AppPaths.ensure(directory)
        let settings = environment.settings
        let previousTab = settings.lastTab
        let model = IslandViewModel(settings: settings)
        let geometry = NotchGeometry.preferredScreen().map(NotchGeometry.init(screen:)) ?? .fallback
        model.update(geometry: geometry, expandedSize: settings.islandSize.expandedSize)
        let canvas = CGSize(width: model.expandedFrameSize.width + 80, height: model.expandedFrameSize.height + 40)

        let root = IslandRootView()
            .environmentObject(model)
            .withAppEnvironment(environment)
            .background(Color(white: 0.6))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: canvas)
        // Fenster außerhalb des sichtbaren Bereichs, damit nichts auf dem Bildschirm erscheint.
        let window = NSWindow(
            contentRect: CGRect(x: -30_000, y: -30_000, width: canvas.width, height: canvas.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()

        func snapshot(_ name: String) async {
            try? await Task.sleep(for: .milliseconds(900))
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            guard let data = capture(hosting) else { return }
            try? data.write(to: directory.appendingPathComponent("\(name).png"))
        }

        await snapshot("collapsed")
        model.setCompactActivity(.music)
        await snapshot("collapsed-music")
        model.setCompactActivity(.calendar)
        await snapshot("collapsed-calendar")
        model.setCompactActivity(.none)
        for tab in IslandTab.allCases {
            model.expand(tab: tab)
            await snapshot("expanded-\(tab.rawValue)")
        }
        // MacBuddy-Zustände
        let buddy = environment.macBuddy
        buddy.debugShow(status: .init(session: "demo", state: .working, title: "Öffnet Safari",
                                      detail: "Schritt 2 von 4", progress: 0.5, canStop: true))
        model.collapse()
        model.setCompactActivity(.macBuddy)
        await snapshot("collapsed-macbuddy")
        model.setCompactActivity(.none)
        model.expand(tab: .macBuddy)
        await snapshot("expanded-macbuddy-status")
        buddy.debugShow(
            status: .init(session: "demo", state: .awaitingConfirmation, title: "Wartet auf Bestätigung", canStop: true),
            confirmation: .init(id: "demo", title: "Datei in den Papierkorb legen",
                                detail: "„Rechnung_2026.pdf“ aus Downloads wird in den Papierkorb gelegt. Du kannst sie von dort wiederherstellen.",
                                category: "Löschen", confirmLabel: "In den Papierkorb", allowsApproval: true)
        )
        await snapshot("expanded-macbuddy-confirmation")
        buddy.debugShow(result: .init(session: "demo", success: true, title: "Erledigt",
                                      text: "Safari ist geöffnet, das Fenster liegt links und Xcode rechts daneben. Musik spielt deine Fokus-Playlist."))
        await snapshot("expanded-macbuddy-result")
        buddy.debugShow()

        // Timer neben der Notch
        model.collapse()
        model.setCompactActivity(.timer)
        await snapshot("collapsed-timer")
        model.setCompactActivity(.none)

        settings.lastTab = previousTab
        window.orderOut(nil)

        // Einstellungsfenster
        let settingsHosting = NSHostingView(rootView: SettingsView().withAppEnvironment(environment))
        let settingsSize = CGSize(width: 520, height: 1180)
        settingsHosting.frame = CGRect(origin: .zero, size: settingsSize)
        let settingsWindow = NSWindow(
            contentRect: CGRect(x: -30_000, y: -30_000, width: settingsSize.width, height: settingsSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        settingsWindow.contentView = settingsHosting
        settingsWindow.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(900))
        settingsHosting.layoutSubtreeIfNeeded()
        settingsHosting.displayIfNeeded()
        if let data = capture(settingsHosting) {
            try? data.write(to: directory.appendingPathComponent("settings.png"))
        }
        settingsWindow.orderOut(nil)
    }

    private static func capture(_ view: NSView) -> Data? {
        guard let layer = view.layer else { return nil }
        let scale: CGFloat = 2
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cgContext = context.cgContext
        cgContext.scaleBy(x: scale, y: scale)
        // Der Layer der Hosting-View ist geometrisch geflippt; für das Bitmap wieder umdrehen.
        if layer.isGeometryFlipped || view.isFlipped {
            cgContext.translateBy(x: 0, y: size.height)
            cgContext.scaleBy(x: 1, y: -1)
        }
        layer.render(in: cgContext)
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
