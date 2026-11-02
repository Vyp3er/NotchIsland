import AppKit
import Combine
import EventKit

/// Termine von heute und morgen über EventKit, plus Hinweis 5 Minuten vor Beginn.
@MainActor
final class CalendarStore: ObservableObject {
    enum Access: Equatable {
        case notDetermined
        case granted
        case denied
    }

    @Published private(set) var access: Access
    /// Noch nicht beendete Termine von heute und morgen, sortiert.
    @Published private(set) var events: [CalendarEvent] = []
    /// Termin, der gerade als Live-Aktivität neben der Notch angekündigt wird.
    @Published private(set) var alertEvent: CalendarEvent?

    private let settings: AppSettings
    private let store = EKEventStore()
    private var isMonitoring = false
    private var timer: Timer?
    private var announcedIDs = Set<String>()
    private var alertDismissal: DispatchWorkItem?
    private var changeObserver: AnyCancellable?

    /// Vorlaufzeit der Ankündigung und wie lange sie sichtbar bleibt.
    private let alertLeadTime: TimeInterval = 5 * 60
    private let alertDuration: TimeInterval = 10

    init(settings: AppSettings) {
        self.settings = settings
        access = Self.currentAccess()
    }

    private static func currentAccess() -> Access {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return .granted }
        if status == .notDetermined { return .notDetermined }
        return .denied
    }

    /// Startet die Überwachung nur, wenn der Zugriff schon erlaubt wurde (keine Anfrage beim Start).
    func start() {
        if access == .granted { beginMonitoring() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        changeObserver = nil
        isMonitoring = false
    }

    /// Der Kalender-Tab wird sichtbar: erst jetzt wird ggf. nach Zugriff gefragt.
    func tabBecameVisible() {
        switch access {
        case .notDetermined: requestAccess()
        case .granted: reload()
        case .denied: access = Self.currentAccess()
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, error in
            if let error {
                Log.calendar.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.access = granted ? .granted : .denied
                if granted { self.beginMonitoring() }
            }
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openCalendarApp() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Laden

    private func beginMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        reload()
        changeObserver = NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func reload() {
        guard access == .granted else { return }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 2, to: startOfToday) else { return }
        let predicate = store.predicateForEvents(withStart: startOfToday, end: end, calendars: nil)
        let now = Date()
        let loaded = store.events(matching: predicate)
            .filter { $0.status != .canceled && $0.endDate > now }
            .map(CalendarEvent.init(event:))
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.start < rhs.start
            }
        if loaded != events { events = loaded }
        checkUpcomingAlert(now: now)
    }

    private func tick() {
        let now = Date()
        // Beendete Termine ausblenden, ohne EventKit neu zu fragen.
        let current = events.filter { $0.end > now }
        if current.count != events.count { events = current }
        checkUpcomingAlert(now: now)
    }

    // MARK: - Abschnitte

    var todayEvents: [CalendarEvent] { events.filter { Calendar.current.isDateInToday($0.start) || $0.isOngoing(at: Date()) } }

    var tomorrowEvents: [CalendarEvent] {
        events.filter { Calendar.current.isDateInTomorrow($0.start) && !$0.isOngoing(at: Date()) }
    }

    /// Nächster Termin mit Uhrzeit (laufend oder bevorstehend).
    var nextTimedEvent: CalendarEvent? {
        events.first(where: { !$0.isAllDay })
    }

    // MARK: - Live-Aktivität

    private func checkUpcomingAlert(now: Date) {
        guard settings.showCalendarActivity else { return }
        guard let upcoming = events.first(where: { event in
            let lead = event.start.timeIntervalSince(now)
            return !event.isAllDay && lead > 0 && lead <= alertLeadTime && !announcedIDs.contains(event.id)
        }) else { return }
        announcedIDs.insert(upcoming.id)
        alertEvent = upcoming
        alertDismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.alertEvent = nil }
        alertDismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + alertDuration, execute: work)
    }
}
