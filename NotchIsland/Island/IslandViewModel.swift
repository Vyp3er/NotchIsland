import SwiftUI

/// Was die zugeklappte Island links und rechts neben der Notch anzeigt.
enum CompactActivity: Equatable {
    case none
    case music
    case calendar
    case macBuddy
    case timer

    /// Tab, der sich beim Klick auf die Aktivität öffnet.
    var tab: IslandTab? {
        switch self {
        case .none: nil
        case .music: .music
        case .calendar: .calendar
        case .macBuddy: .macBuddy
        case .timer: .timer
        }
    }
}

/// Zustand der Island (offen/zu, Tab, Größen). Die Fenster-Logik liegt im `IslandWindowController`.
@MainActor
final class IslandViewModel: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var selectedTab: IslandTab
    @Published private(set) var geometry: NotchGeometry = .fallback
    @Published private(set) var expandedSize: CGSize
    @Published private(set) var compactActivity: CompactActivity = .none
    /// Eine Datei wird gerade über die geöffnete Island gezogen.
    @Published var isDropTargeted = false
    /// Zeiger liegt auf der Notch, die Island ist aber noch zu (kleiner "Atmer" als Vorschau).
    @Published private(set) var isPeeking = false
    /// Zeiger liegt auf einer direkt klickbaren Aktion der Live-Aktivität (MacBuddy-Not-Aus).
    @Published var isPointerOnCompactAction = false

    /// Wird vom AppDelegate gesetzt (Zahnrad in der Island).
    var openSettings: () -> Void = {}
    /// Vom Fenster-Controller gesetzt: Island zuklappen bzw. für Texteingabe zum Key-Window machen.
    var collapseHandler: () -> Void = {}
    var makeKeyForTextInput: () -> Void = {}

    /// Zählt Anfragen, das Eingabefeld des aktiven Tabs zu fokussieren.
    @Published private(set) var textFocusRequest = 0
    private var pendingTextFocus = false

    private let settings: AppSettings

    static let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let closeAnimation = Animation.spring(response: 0.34, dampingFraction: 0.92)
    static let activityAnimation = Animation.spring(response: 0.45, dampingFraction: 0.8)

    init(settings: AppSettings) {
        self.settings = settings
        selectedTab = settings.isVisible(settings.lastTab) ? settings.lastTab : (settings.visibleTabs.first ?? .shelf)
        expandedSize = settings.islandSize.expandedSize
    }

    // MARK: - Zustandswechsel

    func expand(tab: IslandTab? = nil) {
        if let tab, settings.isVisible(tab) {
            selectedTab = tab
            settings.lastTab = tab
        } else if !settings.isVisible(selectedTab), let first = settings.visibleTabs.first {
            selectedTab = first
        }
        guard !isExpanded else { return }
        withAnimation(Self.openAnimation) {
            isExpanded = true
            isPeeking = false
        }
    }

    func requestCollapse() {
        collapseHandler()
    }

    /// Eingabefeld fokussieren (Timer-Tab). Das Panel wird dafür Key-Window, ohne die App zu aktivieren.
    func focusTextInput() {
        makeKeyForTextInput()
        pendingTextFocus = true
        textFocusRequest += 1
    }

    /// Für Ansichten, die erst nach der Anfrage erscheinen.
    func consumePendingTextFocus() -> Bool {
        defer { pendingTextFocus = false }
        return pendingTextFocus
    }

    func setPeeking(_ peeking: Bool) {
        let value = peeking && !isExpanded
        guard value != isPeeking else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPeeking = value }
    }

    func collapse() {
        guard isExpanded else { return }
        withAnimation(Self.closeAnimation) {
            isExpanded = false
            isDropTargeted = false
        }
    }

    func select(_ tab: IslandTab) {
        guard tab != selectedTab else { return }
        withAnimation(.snappy(duration: 0.28)) { selectedTab = tab }
        settings.lastTab = tab
    }

    /// Nach Änderungen an den sichtbaren Tabs sicherstellen, dass ein gültiger Tab gewählt ist.
    func validateSelection() {
        if !settings.isVisible(selectedTab), let first = settings.visibleTabs.first {
            selectedTab = first
        }
    }

    func setCompactActivity(_ activity: CompactActivity) {
        guard activity != compactActivity else { return }
        withAnimation(Self.activityAnimation) { compactActivity = activity }
    }

    func update(geometry: NotchGeometry, expandedSize: CGSize) {
        if geometry != self.geometry { self.geometry = geometry }
        if expandedSize != self.expandedSize {
            withAnimation(Self.openAnimation) { self.expandedSize = expandedSize }
        }
    }

    // MARK: - Maße

    var notchWidth: CGFloat { geometry.notchRect.width }
    var notchHeight: CGFloat { geometry.notchRect.height }

    /// Konkave Rundung oben (geht in den Bildschirmrand über).
    var collapsedTopRadius: CGFloat { 5 }
    var expandedTopRadius: CGFloat { 14 }
    var collapsedBottomRadius: CGFloat { min(10, notchHeight / 2.6) }
    var expandedBottomRadius: CGFloat { 32 }

    /// Breite der "Ohren" links und rechts neben der Notch im zugeklappten Zustand.
    var earWidth: CGFloat {
        switch compactActivity {
        case .none: 0
        case .music: notchHeight + 10
        case .calendar: 116
        case .macBuddy: 132
        case .timer: 104
        }
    }

    var collapsedFrameSize: CGSize {
        CGSize(width: notchWidth + 2 * earWidth + 2 * collapsedTopRadius, height: notchHeight)
    }

    var expandedFrameSize: CGSize {
        CGSize(width: max(expandedSize.width, notchWidth + 400), height: max(expandedSize.height, notchHeight + 140))
    }

    var currentFrameSize: CGSize { isExpanded ? expandedFrameSize : collapsedFrameSize }

    /// Höhe der oberen Leiste (Tab-Icons links, Aktionen rechts, Notch in der Mitte).
    var headerHeight: CGFloat { max(notchHeight, 28) }

    /// Seitlicher Innenabstand des Inhalts der geöffneten Island.
    var contentHorizontalPadding: CGFloat { expandedTopRadius + 14 }

    /// Breite der Spalten links und rechts neben der Notch in der Kopfzeile.
    var headerSideWidth: CGFloat {
        max(0, (expandedFrameSize.width - 2 * contentHorizontalPadding - notchWidth - 24) / 2)
    }
}
