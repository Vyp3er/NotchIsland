import Foundation
import ServiceManagement

/// Autostart über `SMAppService.mainApp`.
@MainActor
enum LoginItemManager {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    static var requiresApproval: Bool { status == .requiresApproval }

    /// Login-Items sollten auf eine stabile App-Kopie zeigen, nicht auf einen DerivedData-Build.
    static var isInstalledInApplications: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard status == .enabled || status == .requiresApproval else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    /// Beim Start: Autostart registrieren, wenn gewünscht und die App im Programme-Ordner liegt.
    static func applyPreferenceOnLaunch(settings: AppSettings) {
        guard settings.launchAtLogin, isInstalledInApplications else { return }
        guard status != .enabled, status != .requiresApproval else { return }
        do {
            try SMAppService.mainApp.register()
            Log.app.info("Login item registered")
        } catch {
            Log.app.error("Login item registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
