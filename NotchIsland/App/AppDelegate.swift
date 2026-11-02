import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var statusBar: StatusBarController?
    private var islandController: IslandWindowController?
    private var settingsWindow: SettingsWindowController?
    private let crashRecovery = CrashRecovery()
    private var terminationSignal: DispatchSourceSignal?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Schreiben in eine geschlossene Pipe (z. B. zum Wächter) darf die App nicht beenden.
        signal(SIGPIPE, SIG_IGN)
        handleTerminationSignal()
        installEditMenu()

        let environment = AppEnvironment()
        self.environment = environment

        #if DEBUG
        if let directory = DebugSnapshots.outputDirectory {
            environment.start()
            DebugSnapshots.run(environment: environment, to: directory)
            return
        }
        #endif

        LoginItemManager.applyPreferenceOnLaunch(settings: environment.settings)

        let settingsWindow = SettingsWindowController(environment: environment)
        self.settingsWindow = settingsWindow

        let island = IslandWindowController(environment: environment)
        environment.island.openSettings = { [weak settingsWindow] in settingsWindow?.show() }
        islandController = island

        statusBar = StatusBarController(
            openSettings: { [weak settingsWindow] in settingsWindow?.show() },
            clearShelf: { [weak environment] in environment?.shelf.removeAll() }
        )

        environment.start()
        island.start()

        // Absturz-Neustart nur für die installierte Kopie (sonst würde z. B. Xcodes Stopp-Button neu starten).
        environment.settings.$restartAfterCrash
            .sink { [weak self] enabled in
                self?.crashRecovery.setEnabled(enabled && LoginItemManager.isInstalledInApplications)
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Normales Beenden: Wächter informieren, damit er die App nicht neu startet.
        crashRecovery.disarm()
        environment?.stop()
    }

    /// Ohne Hauptmenü funktionieren ⌘C/⌘V & Co. in Textfeldern nicht. Das Menü bleibt unsichtbar
    /// (die App hat keine Menüleiste), liefert aber die Tastenkürzel.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "NotchIsland")
        mainMenu.addItem(appItem)

        let editMenu = NSMenu(title: "Bearbeiten")
        editMenu.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    /// SIGTERM (z. B. `pkill`, Installationsskript) wie ein normales Beenden behandeln.
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Doppelklick auf die App im Finder öffnet die Einstellungen.
        settingsWindow?.show()
        return false
    }
}
