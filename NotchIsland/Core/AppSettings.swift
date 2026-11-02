import Foundation
import Combine

enum IslandSize: String, CaseIterable, Identifiable {
    case compact
    case standard
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Kompakt"
        case .standard: "Standard"
        case .large: "Groß"
        }
    }

    /// Größe der ausgeklappten Island in Punkten.
    var expandedSize: CGSize {
        switch self {
        case .compact: CGSize(width: 560, height: 196)
        case .standard: CGSize(width: 640, height: 232)
        case .large: CGSize(width: 740, height: 284)
        }
    }
}

enum MusicSourceMode: String, CaseIterable, Identifiable {
    /// MediaRemote-Adapter (alle Apps), AppleScript als Fallback für Musik und Spotify.
    case automatic
    /// Nur AppleScript (Musik und Spotify).
    case appleScriptOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatisch (alle Apps)"
        case .appleScriptOnly: "Nur Musik & Spotify (AppleScript)"
        }
    }
}

/// Alle Einstellungen, in `UserDefaults` gespeichert.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let tabOrder = "tabOrder"
        static let hiddenTabs = "hiddenTabs"
        static let lastTab = "lastTab"
        static let openDelay = "openDelay"
        static let closeDelay = "closeDelay"
        static let islandSize = "islandSize"
        static let removeAfterDragOut = "removeAfterDragOut"
        static let launchAtLogin = "launchAtLogin"
        static let restartAfterCrash = "restartAfterCrash"
        static let showMusicActivity = "showMusicActivity"
        static let showCalendarActivity = "showCalendarActivity"
        static let hapticFeedback = "hapticFeedback"
        static let musicSource = "musicSource"
        static let clipboardLimit = "clipboardLimit"
        static let macBuddyEnabled = "macBuddyEnabled"
        static let macBuddyAutoExpand = "macBuddyAutoExpand"
        static let showMacBuddyActivity = "showMacBuddyActivity"
        static let timerSound = "timerSound"
        static let timerAutoExpand = "timerAutoExpand"
        static let showTimerActivity = "showTimerActivity"
    }

    private let defaults: UserDefaults

    @Published var tabOrder: [IslandTab] {
        didSet { defaults.set(tabOrder.map(\.rawValue), forKey: Key.tabOrder) }
    }

    @Published var hiddenTabs: Set<IslandTab> {
        didSet { defaults.set(hiddenTabs.map(\.rawValue).sorted(), forKey: Key.hiddenTabs) }
    }

    @Published var lastTab: IslandTab {
        didSet { defaults.set(lastTab.rawValue, forKey: Key.lastTab) }
    }

    /// Verzögerung, bevor die Island beim Hovern aufklappt (Sekunden).
    @Published var openDelay: Double {
        didSet { defaults.set(openDelay, forKey: Key.openDelay) }
    }

    /// Verzögerung, bevor die Island nach dem Verlassen zuklappt (Sekunden).
    @Published var closeDelay: Double {
        didSet { defaults.set(closeDelay, forKey: Key.closeDelay) }
    }

    @Published var islandSize: IslandSize {
        didSet { defaults.set(islandSize.rawValue, forKey: Key.islandSize) }
    }

    @Published var removeAfterDragOut: Bool {
        didSet { defaults.set(removeAfterDragOut, forKey: Key.removeAfterDragOut) }
    }

    /// Wunsch des Nutzers; der tatsächliche Status kommt von `SMAppService`.
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    /// Nach einem Absturz automatisch neu starten (nur für die Kopie in /Applications).
    @Published var restartAfterCrash: Bool {
        didSet { defaults.set(restartAfterCrash, forKey: Key.restartAfterCrash) }
    }

    @Published var showMusicActivity: Bool {
        didSet { defaults.set(showMusicActivity, forKey: Key.showMusicActivity) }
    }

    @Published var showCalendarActivity: Bool {
        didSet { defaults.set(showCalendarActivity, forKey: Key.showCalendarActivity) }
    }

    @Published var hapticFeedback: Bool {
        didSet { defaults.set(hapticFeedback, forKey: Key.hapticFeedback) }
    }

    @Published var musicSource: MusicSourceMode {
        didSet { defaults.set(musicSource.rawValue, forKey: Key.musicSource) }
    }

    @Published var clipboardLimit: Int {
        didSet { defaults.set(clipboardLimit, forKey: Key.clipboardLimit) }
    }

    /// Status, Ergebnisse und Bestätigungen von MacBuddy empfangen.
    @Published var macBuddyEnabled: Bool {
        didSet { defaults.set(macBuddyEnabled, forKey: Key.macBuddyEnabled) }
    }

    /// Bei Bestätigungsanfragen von MacBuddy die Island automatisch aufklappen.
    @Published var macBuddyAutoExpand: Bool {
        didSet { defaults.set(macBuddyAutoExpand, forKey: Key.macBuddyAutoExpand) }
    }

    @Published var showMacBuddyActivity: Bool {
        didSet { defaults.set(showMacBuddyActivity, forKey: Key.showMacBuddyActivity) }
    }

    /// Ton, solange ein abgelaufener Timer klingelt.
    @Published var timerSound: Bool {
        didSet { defaults.set(timerSound, forKey: Key.timerSound) }
    }

    /// Beim Ablauf eines Timers die Island im Timer-Tab aufklappen.
    @Published var timerAutoExpand: Bool {
        didSet { defaults.set(timerAutoExpand, forKey: Key.timerAutoExpand) }
    }

    @Published var showTimerActivity: Bool {
        didSet { defaults.set(showTimerActivity, forKey: Key.showTimerActivity) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedOrder = (defaults.stringArray(forKey: Key.tabOrder) ?? []).compactMap(IslandTab.init(rawValue:))
        var order = storedOrder.reduce(into: [IslandTab]()) { result, tab in
            if !result.contains(tab) { result.append(tab) }
        }
        for tab in IslandTab.allCases where !order.contains(tab) { order.append(tab) }
        tabOrder = order

        var hidden = Set((defaults.stringArray(forKey: Key.hiddenTabs) ?? []).compactMap(IslandTab.init(rawValue:)))
        if hidden.count >= IslandTab.allCases.count { hidden = [] }
        hiddenTabs = hidden

        lastTab = defaults.string(forKey: Key.lastTab).flatMap(IslandTab.init(rawValue:)) ?? .shelf
        openDelay = defaults.object(forKey: Key.openDelay) as? Double ?? 0.12
        closeDelay = defaults.object(forKey: Key.closeDelay) as? Double ?? 0.3
        islandSize = defaults.string(forKey: Key.islandSize).flatMap(IslandSize.init(rawValue:)) ?? .standard
        removeAfterDragOut = defaults.object(forKey: Key.removeAfterDragOut) as? Bool ?? false
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true
        restartAfterCrash = defaults.object(forKey: Key.restartAfterCrash) as? Bool ?? true
        showMusicActivity = defaults.object(forKey: Key.showMusicActivity) as? Bool ?? true
        showCalendarActivity = defaults.object(forKey: Key.showCalendarActivity) as? Bool ?? true
        hapticFeedback = defaults.object(forKey: Key.hapticFeedback) as? Bool ?? true
        musicSource = defaults.string(forKey: Key.musicSource).flatMap(MusicSourceMode.init(rawValue:)) ?? .automatic
        clipboardLimit = defaults.object(forKey: Key.clipboardLimit) as? Int ?? 30
        macBuddyEnabled = defaults.object(forKey: Key.macBuddyEnabled) as? Bool ?? true
        macBuddyAutoExpand = defaults.object(forKey: Key.macBuddyAutoExpand) as? Bool ?? true
        showMacBuddyActivity = defaults.object(forKey: Key.showMacBuddyActivity) as? Bool ?? true
        timerSound = defaults.object(forKey: Key.timerSound) as? Bool ?? true
        timerAutoExpand = defaults.object(forKey: Key.timerAutoExpand) as? Bool ?? true
        showTimerActivity = defaults.object(forKey: Key.showTimerActivity) as? Bool ?? true
    }

    var visibleTabs: [IslandTab] {
        tabOrder.filter { !hiddenTabs.contains($0) }
    }

    func isVisible(_ tab: IslandTab) -> Bool {
        !hiddenTabs.contains(tab)
    }

    /// Blendet einen Tab ein oder aus; mindestens ein Tab bleibt immer sichtbar.
    func setVisible(_ visible: Bool, for tab: IslandTab) {
        if visible {
            hiddenTabs.remove(tab)
        } else if visibleTabs.count > 1 {
            hiddenTabs.insert(tab)
        }
    }

    func moveTabs(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = tabOrder
        let moving = source.sorted().map { order[$0] }
        for index in source.sorted(by: >) { order.remove(at: index) }
        let removedBefore = source.filter { $0 < destination }.count
        let target = max(0, min(order.count, destination - removedBefore))
        order.insert(contentsOf: moving, at: target)
        tabOrder = order
    }

    func resetTabs() {
        tabOrder = IslandTab.allCases
        hiddenTabs = []
    }
}
