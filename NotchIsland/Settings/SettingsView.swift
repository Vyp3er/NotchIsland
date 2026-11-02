import ServiceManagement
import SwiftUI

/// Einstellungen: Allgemein, Island, Tabs, Ablage, Musik, Zwischenablage.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var clipboard: ClipboardHistoryStore
    @EnvironmentObject private var macBuddy: MacBuddyIslandClient

    @State private var loginStatus = LoginItemManager.status
    @State private var loginError: String?

    var body: some View {
        Form {
            generalSection
            islandSection
            tabsSection
            shelfSection
            musicSection
            clipboardSection
            macBuddySection
            timerSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 560, idealHeight: 640)
        .onAppear { loginStatus = LoginItemManager.status }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Nach einer Freigabe in den Systemeinstellungen den Status aktualisieren.
            loginStatus = LoginItemManager.status
        }
    }

    // MARK: - Allgemein

    private var generalSection: some View {
        Section("Allgemein") {
            Toggle("Beim Login starten", isOn: Binding(
                get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                set: setLaunchAtLogin
            ))
            if loginStatus == .requiresApproval {
                HStack {
                    Label("Wartet auf Freigabe unter Allgemein → Anmeldeobjekte.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Öffnen") { LoginItemManager.openSystemSettings() }
                }
                .font(.callout)
            }
            if !LoginItemManager.isInstalledInApplications {
                Label("Die App liegt nicht im Programme-Ordner. Für den Autostart am besten nach /Programme kopieren (siehe README).", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let loginError {
                Text(loginError).font(.callout).foregroundStyle(.red)
            }
            Toggle("Nach einem Absturz automatisch neu starten", isOn: $settings.restartAfterCrash)
                .help("Startet NotchIsland neu, wenn die App abstürzt oder sofort beendet wird. Normales Beenden über das Menü bleibt beendet.")
            Toggle("Haptisches Feedback beim Aufklappen", isOn: $settings.hapticFeedback)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        do {
            try LoginItemManager.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = "Autostart konnte nicht geändert werden: \(error.localizedDescription)"
        }
        loginStatus = LoginItemManager.status
    }

    // MARK: - Island

    private var islandSection: some View {
        Section("Island") {
            Picker("Größe", selection: $settings.islandSize) {
                ForEach(IslandSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Öffnen nach") {
                HStack {
                    Slider(value: $settings.openDelay, in: 0...1, step: 0.05)
                    Text(milliseconds(settings.openDelay))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            }
            LabeledContent("Schließen nach") {
                HStack {
                    Slider(value: $settings.closeDelay, in: 0.1...1.5, step: 0.05)
                    Text(milliseconds(settings.closeDelay))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            }
            Toggle("Musik neben der Notch anzeigen", isOn: $settings.showMusicActivity)
            Toggle("Termin 5 Minuten vorher neben der Notch ankündigen", isOn: $settings.showCalendarActivity)
        }
    }

    private func milliseconds(_ seconds: Double) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }

    // MARK: - Tabs

    private var tabsSection: some View {
        Section {
            ForEach(Array(settings.tabOrder.enumerated()), id: \.element) { index, tab in
                HStack(spacing: 10) {
                    Image(systemName: tab.systemImage)
                        .frame(width: 20)
                        .foregroundStyle(settings.isVisible(tab) ? Color.accentColor : Color.secondary)
                    Toggle(tab.title, isOn: Binding(
                        get: { settings.isVisible(tab) },
                        set: { settings.setVisible($0, for: tab) }
                    ))
                    .disabled(settings.isVisible(tab) && settings.visibleTabs.count == 1)
                    Spacer()
                    Button {
                        settings.moveTabs(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .help("Nach oben")
                    Button {
                        settings.moveTabs(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == settings.tabOrder.count - 1)
                    .help("Nach unten")
                }
            }
            .onMove { source, destination in
                settings.moveTabs(fromOffsets: source, toOffset: destination)
            }
            Button("Standardreihenfolge wiederherstellen") { settings.resetTabs() }
        } header: {
            Text("Tabs")
        } footer: {
            Text("Ein- oder ausblenden und die Reihenfolge in der Island festlegen. Ohne Zwischenablage-Tab wird die Zwischenablage nicht beobachtet.")
        }
    }

    // MARK: - Ablage

    private var shelfSection: some View {
        Section {
            Toggle("Elemente nach dem Herausziehen aus der Ablage entfernen", isOn: $settings.removeAfterDragOut)
            Button("Ordner für Bilder, Texte und Links im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([AppPaths.shelfFilesDirectory])
            }
        } header: {
            Text("Ablage")
        } footer: {
            Text("Dateien werden nur verknüpft, nicht kopiert. Herausziehen kopiert; mit gedrückter ⌘-Taste wird die Datei verschoben.")
        }
    }

    // MARK: - Musik

    private var musicSection: some View {
        Section {
            Picker("Quelle", selection: $settings.musicSource) {
                ForEach(MusicSourceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            LabeledContent("Aktiv", value: nowPlaying.backend.title)
        } header: {
            Text("Musik")
        } footer: {
            Text("Automatisch nutzt den mediaremote-adapter (Musik, Spotify, Browser, …). Funktioniert er nach einem macOS-Update nicht mehr, wird auf AppleScript für Musik und Spotify umgeschaltet.")
        }
    }

    // MARK: - Zwischenablage

    private var clipboardSection: some View {
        Section {
            Stepper(value: $settings.clipboardLimit, in: 10...100, step: 5) {
                LabeledContent("Einträge im Verlauf", value: "\(settings.clipboardLimit)")
            }
            HStack {
                Button("Verlauf leeren") { clipboard.clear() }
                Button("Alles inkl. Angehefteter löschen", role: .destructive) { clipboard.clear(includingPinned: true) }
            }
        } header: {
            Text("Zwischenablage")
        } footer: {
            Text("Der Verlauf wird nur lokal gespeichert. Inhalte aus Passwortmanagern (ConcealedType/TransientType) werden ignoriert.")
        }
    }

    // MARK: - MacBuddy

    private var macBuddySection: some View {
        Section {
            Toggle("Status, Ergebnisse und Bestätigungen von MacBuddy anzeigen", isOn: $settings.macBuddyEnabled)
            Toggle("Bei Bestätigungen automatisch aufklappen", isOn: $settings.macBuddyAutoExpand)
                .disabled(!settings.macBuddyEnabled)
            Toggle("Status und Not-Aus neben der Notch anzeigen", isOn: $settings.showMacBuddyActivity)
                .disabled(!settings.macBuddyEnabled)
            LabeledContent("MacBuddy", value: macBuddyState)
        } header: {
            Text("MacBuddy")
        } footer: {
            Text("Verbindung über macOS-Benachrichtigungen. „Stopp“ rechts neben der Notch bricht MacBuddy sofort ab. Ob riskante Aktionen auch hier bestätigt werden dürfen, legst du in MacBuddy unter Einstellungen › NotchIsland fest.")
        }
    }

    private var macBuddyState: String {
        if macBuddy.isMacBuddyRunning { return "Läuft" }
        return macBuddy.isMacBuddyInstalled ? "Beendet" : "Nicht installiert"
    }

    // MARK: - Timer

    private var timerSection: some View {
        Section {
            Toggle("Ton beim Ablauf", isOn: $settings.timerSound)
            Toggle("Island beim Ablauf aufklappen", isOn: $settings.timerAutoExpand)
            Toggle("Restzeit neben der Notch anzeigen", isOn: $settings.showTimerActivity)
        } header: {
            Text("Timer")
        } footer: {
            Text("Eingabe z. B. „5min“, „15 Minuten“, „1h30“, „halbe Stunde“, „@17:30“, „@5pm“, „um 18 Uhr“ oder „Pizza 12 min“. Mit „@“ ist immer eine Uhrzeit gemeint. Timer laufen auch nach einem Neustart weiter.")
        }
    }

    // MARK: - Info

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            Button("NotchIsland beenden") { NSApp.terminate(nil) }
        }
    }
}
