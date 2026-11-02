// Basiert auf MacBuddy/NotchIslandIntegration/MacBuddyIslandClient.swift.
// Empfängt Status, Ergebnisse und Bestätigungsanfragen von MacBuddy und schickt
// Befehle (Not-Aus, Bestätigen, Ablehnen, Öffnen) zurück.
//
// Änderungen gegenüber dem Original:
// - Status und Ergebnis haben getrennte Timer. Im Original setzt das auf `result` folgende
//   `status(done)` den gemeinsamen Timer auf 2,5 s zurück, das Ergebnis verschwand dadurch zu früh.
// - Solange der MacBuddy-Tab offen ist, bleibt das Ergebnis stehen (bis "OK" oder Zuklappen).
// - Beendet sich MacBuddy (oder stürzt ab), wird die Anzeige zurückgesetzt.

import AppKit
import Combine
import Foundation

@MainActor
final class MacBuddyIslandClient: ObservableObject {
    static let bundleIdentifier = "de.vincentschmitt.MacBuddy"

    @Published private(set) var status: MacBuddyIsland.StatusMessage?
    @Published private(set) var result: MacBuddyIsland.ResultMessage?
    @Published private(set) var confirmation: MacBuddyIsland.ConfirmationRequest?
    @Published private(set) var isMacBuddyRunning = false

    /// Soll die Island gerade etwas von MacBuddy zeigen?
    var isActive: Bool {
        if confirmation != nil || result != nil { return true }
        guard let status else { return false }
        return status.state != .idle
    }

    /// Not-Aus ist sinnvoll (laufende Aktion oder offene Bestätigung).
    var canStop: Bool {
        status?.canStop == true || confirmation != nil
    }

    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var statusClear: Task<Void, Never>?
    private var resultClear: Task<Void, Never>?
    /// Der MacBuddy-Tab ist gerade sichtbar.
    private var isPresented = false
    private var resultExpiredWhilePresented = false
    private let appVersion: String

    init(appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") {
        self.appVersion = appVersion
    }

    var isRunning: Bool { !observers.isEmpty }

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observe(center, MacBuddyIsland.Name.status) { [weak self] payload in
            guard let self, let message = MacBuddyIsland.decode(MacBuddyIsland.StatusMessage.self, from: payload) else { return }
            self.isMacBuddyRunning = true
            switch message.state {
            case .idle:
                self.status = nil
            case .done, .failed, .cancelled:
                self.status = message
                self.scheduleStatusClear(after: 2.5)
            default:
                self.statusClear?.cancel()
                self.status = message
            }
        }
        observe(center, MacBuddyIsland.Name.result) { [weak self] payload in
            guard let self, let message = MacBuddyIsland.decode(MacBuddyIsland.ResultMessage.self, from: payload) else { return }
            self.result = message
            self.scheduleResultClear(after: 6)
        }
        observe(center, MacBuddyIsland.Name.confirmationRequest) { [weak self] payload in
            guard let self, let message = MacBuddyIsland.decode(MacBuddyIsland.ConfirmationRequest.self, from: payload) else { return }
            self.isMacBuddyRunning = true
            self.confirmation = message
        }
        observe(center, MacBuddyIsland.Name.confirmationResolved) { [weak self] payload in
            guard let self, let message = MacBuddyIsland.decode(MacBuddyIsland.ConfirmationResolved.self, from: payload),
                  self.confirmation?.id == message.id else { return }
            self.confirmation = nil
        }
        observe(center, MacBuddyIsland.Name.ping) { [weak self] _ in
            self?.isMacBuddyRunning = true
            self?.sayHello()
        }
        observeMacBuddyLifecycle()
        sayHello()
    }

    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        reset()
    }

    /// Wird aufgerufen, wenn der MacBuddy-Tab sichtbar oder unsichtbar wird.
    func setPresented(_ presented: Bool) {
        isPresented = presented
        if !presented, resultExpiredWhilePresented {
            resultExpiredWhilePresented = false
            result = nil
        }
    }

    // MARK: Befehle an MacBuddy

    /// Not-Aus: bricht jede laufende Aktion sofort ab.
    func stopMacBuddy() {
        MacBuddyIsland.post(MacBuddyIsland.Name.command, MacBuddyIsland.Command(command: .stop))
    }

    func approve() {
        guard let confirmation, confirmation.allowsApproval else { return }
        MacBuddyIsland.post(MacBuddyIsland.Name.command, MacBuddyIsland.Command(command: .approve, id: confirmation.id))
        self.confirmation = nil
    }

    func deny() {
        guard let confirmation else { return }
        MacBuddyIsland.post(MacBuddyIsland.Name.command, MacBuddyIsland.Command(command: .deny, id: confirmation.id))
        self.confirmation = nil
    }

    /// Zeigt das MacBuddy-Panel; läuft MacBuddy nicht, wird die App gestartet.
    func openMacBuddy() {
        if isMacBuddyRunning {
            MacBuddyIsland.post(MacBuddyIsland.Name.command, MacBuddyIsland.Command(command: .open))
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    var isMacBuddyInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil
    }

    func dismissResult() {
        resultClear?.cancel()
        resultExpiredWhilePresented = false
        result = nil
    }

    // MARK: Intern

    private func reset() {
        statusClear?.cancel()
        resultClear?.cancel()
        status = nil
        result = nil
        confirmation = nil
        resultExpiredWhilePresented = false
    }

    private func sayHello() {
        MacBuddyIsland.post(MacBuddyIsland.Name.hello, MacBuddyIsland.Hello(version: appVersion))
    }

    private func observe(_ center: DistributedNotificationCenter, _ name: Notification.Name, handler: @escaping @MainActor (Any?) -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
            let payload = note.object
            MainActor.assumeIsolated { handler(payload) }
        })
    }

    /// MacBuddy startet oder beendet sich: Laufstatus merken, bei Ende alles zurücksetzen.
    private func observeMacBuddyLifecycle() {
        isMacBuddyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
        let center = NSWorkspace.shared.notificationCenter
        let launched = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, bundleID == Self.bundleIdentifier else { return }
                self.isMacBuddyRunning = true
                self.sayHello()
            }
        }
        let terminated = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, bundleID == Self.bundleIdentifier else { return }
                self.isMacBuddyRunning = false
                self.reset()
            }
        }
        workspaceObservers = [launched, terminated]
    }

    private func scheduleStatusClear(after seconds: Double) {
        statusClear?.cancel()
        statusClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if let status = self.status, [.done, .failed, .cancelled].contains(status.state) { self.status = nil }
        }
    }

    private func scheduleResultClear(after seconds: Double) {
        resultClear?.cancel()
        resultExpiredWhilePresented = false
        resultClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // Liest der Nutzer gerade im MacBuddy-Tab, erst beim Schließen ausblenden.
            if self.isPresented {
                self.resultExpiredWhilePresented = true
            } else {
                self.result = nil
            }
        }
    }

    #if DEBUG
    /// Beispielzustände für `DebugSnapshots`.
    func debugShow(status: MacBuddyIsland.StatusMessage? = nil,
                   result: MacBuddyIsland.ResultMessage? = nil,
                   confirmation: MacBuddyIsland.ConfirmationRequest? = nil) {
        statusClear?.cancel()
        resultClear?.cancel()
        self.status = status
        self.result = result
        self.confirmation = confirmation
    }
    #endif
}
