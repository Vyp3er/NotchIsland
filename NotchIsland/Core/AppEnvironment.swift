import Foundation
import Combine

/// Hält alle Dienste und verdrahtet sie miteinander.
@MainActor
final class AppEnvironment {
    let settings: AppSettings
    let island: IslandViewModel
    let shelf: ShelfStore
    let nowPlaying: NowPlayingService
    let camera: CameraController
    let calendar: CalendarStore
    let clipboard: ClipboardHistoryStore
    let macBuddy: MacBuddyIslandClient
    let timers: TimerStore

    private var cancellables = Set<AnyCancellable>()

    init() {
        let settings = AppSettings()
        self.settings = settings
        island = IslandViewModel(settings: settings)
        shelf = ShelfStore(settings: settings)
        nowPlaying = NowPlayingService(settings: settings)
        camera = CameraController()
        calendar = CalendarStore(settings: settings)
        clipboard = ClipboardHistoryStore(settings: settings)
        macBuddy = MacBuddyIslandClient()
        timers = TimerStore(settings: settings)
    }

    /// Solange `true`, klappt die Island nicht automatisch zu: eine MacBuddy-Bestätigung wartet im offenen Tab.
    /// Ebenso, solange ein Timer klingelt oder im Timer-Feld getippt wird.
    var keepsIslandOpen: Bool {
        guard island.isExpanded else { return false }
        switch island.selectedTab {
        case .macBuddy: return macBuddy.confirmation != nil
        case .timer: return timers.isRinging || (timers.isEditingInput && !timers.input.isEmpty)
        default: return false
        }
    }

    func start() {
        nowPlaying.start()
        calendar.start()

        // @Published meldet vor dem Setzen; neue Werte daher im nächsten Durchlauf lesen.
        Publishers.MergeMany(
            nowPlaying.$isActivelyPlaying.map { _ in () }.eraseToAnyPublisher(),
            settings.$showMusicActivity.map { _ in () }.eraseToAnyPublisher(),
            calendar.$alertEvent.map { _ in () }.eraseToAnyPublisher(),
            settings.$showCalendarActivity.map { _ in () }.eraseToAnyPublisher(),
            macBuddy.$status.map { _ in () }.eraseToAnyPublisher(),
            macBuddy.$result.map { _ in () }.eraseToAnyPublisher(),
            macBuddy.$confirmation.map { _ in () }.eraseToAnyPublisher(),
            settings.$showMacBuddyActivity.map { _ in () }.eraseToAnyPublisher(),
            timers.$timers.map { _ in () }.eraseToAnyPublisher(),
            timers.$ringingIDs.map { _ in () }.eraseToAnyPublisher(),
            settings.$showTimerActivity.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] _ in DispatchQueue.main.async { self?.updateCompactActivity() } }
        .store(in: &cancellables)

        // MacBuddy-Anbindung (DistributedNotificationCenter) nach Einstellung.
        settings.$macBuddyEnabled
            .sink { [weak self] enabled in
                if enabled { self?.macBuddy.start() } else { self?.macBuddy.stop() }
            }
            .store(in: &cancellables)

        // Zwischenablage nur beobachten, solange der Tab eingeblendet ist.
        settings.$hiddenTabs
            .sink { [weak self] hidden in self?.clipboard.setMonitoring(!hidden.contains(.clipboard)) }
            .store(in: &cancellables)

        // Tab-Lebenszyklus: Module arbeiten nur, solange ihr Tab sichtbar ist.
        Publishers.CombineLatest(island.$isExpanded, island.$selectedTab)
            .sink { [weak self] expanded, tab in
                self?.tabVisibilityChanged(expanded ? tab : nil)
            }
            .store(in: &cancellables)
    }

    func stop() {
        camera.setActive(false)
        nowPlaying.stop()
        calendar.stop()
        clipboard.setMonitoring(false)
        macBuddy.stop()
    }

    private func tabVisibilityChanged(_ visibleTab: IslandTab?) {
        shelf.setVisible(visibleTab == .shelf)
        // Kamera sofort freigeben, sobald der Tab nicht mehr sichtbar ist (LED aus).
        camera.setActive(visibleTab == .camera)
        if visibleTab == .calendar { calendar.tabBecameVisible() }
        macBuddy.setPresented(visibleTab == .macBuddy)
    }

    /// Vorrang: MacBuddy (Not-Aus, Bestätigung) › klingelnder Timer › Termin-Hinweis › laufender Timer › Musik.
    private func updateCompactActivity() {
        if settings.macBuddyEnabled, settings.showMacBuddyActivity, macBuddy.isActive {
            island.setCompactActivity(.macBuddy)
        } else if settings.showTimerActivity, timers.isRinging {
            island.setCompactActivity(.timer)
        } else if settings.showCalendarActivity, calendar.alertEvent != nil {
            island.setCompactActivity(.calendar)
        } else if settings.showTimerActivity, timers.nextRunning != nil {
            island.setCompactActivity(.timer)
        } else if settings.showMusicActivity, nowPlaying.isActivelyPlaying {
            island.setCompactActivity(.music)
        } else {
            island.setCompactActivity(.none)
        }
    }

    #if DEBUG
    /// Beispieldaten für `DebugSnapshots`.
    func prepareDebugSnapshot() {
        shelf.debugAddSamples()
        clipboard.debugAddSamples()
        timers.debugAddSamples()
    }
    #endif
}
