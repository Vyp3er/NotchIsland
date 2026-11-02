import AppKit
import Combine

/// Ein laufender, pausierter oder abgelaufener Timer.
struct IslandTimer: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String?
    var endDate: Date
    var totalDuration: TimeInterval
    var isClockTime: Bool
    /// Restzeit, solange der Timer pausiert ist.
    var pausedRemaining: TimeInterval?
    /// Zeitpunkt des Ablaufs; danach steht der Timer als "Abgelaufen" in der Liste.
    var finishedAt: Date?

    var isFinished: Bool { finishedAt != nil }
    var isPaused: Bool { pausedRemaining != nil && !isFinished }
    var isRunning: Bool { !isPaused && !isFinished }

    var title: String {
        if let label { return label }
        return isClockTime
            ? "Bis \(endDate.formatted(date: .omitted, time: .shortened))"
            : TimerFormat.duration(totalDuration)
    }

    func remaining(at date: Date) -> TimeInterval {
        if isFinished { return 0 }
        if let pausedRemaining { return pausedRemaining }
        return max(0, endDate.timeIntervalSince(date))
    }

    /// Abgelaufener Anteil (0…1).
    func progress(at date: Date) -> Double {
        guard totalDuration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: date) / totalDuration))
    }
}

/// Timer-Tab: Eingabe, mehrere Timer, Alarm beim Ablauf. Timer überstehen einen Neustart.
@MainActor
final class TimerStore: ObservableObject {
    @Published private(set) var timers: [IslandTimer] = []
    /// Abgelaufene Timer, die gerade klingeln.
    @Published private(set) var ringingIDs: Set<UUID> = []
    /// Text im Eingabefeld (bleibt beim Zuklappen erhalten).
    @Published var input = ""
    /// Das Eingabefeld hat gerade den Tastaturfokus.
    @Published var isEditingInput = false

    private let settings: AppSettings
    private var ticker: Timer?
    private var alarmTimer: Timer?
    private var ringingSince: [UUID: Date] = [:]

    /// So lange klingelt ein abgelaufener Timer höchstens.
    private let maxRingDuration: TimeInterval = 30

    init(settings: AppSettings) {
        self.settings = settings
        load()
        catchUpAfterLaunch()
        updateTicker()
    }

    var isRinging: Bool { !ringingIDs.isEmpty }

    /// Nächster laufender Timer (für die Anzeige neben der Notch).
    var nextRunning: IslandTimer? {
        timers.filter(\.isRunning).min { $0.endDate < $1.endDate }
    }

    var ringingTimer: IslandTimer? {
        timers.first { ringingIDs.contains($0.id) }
    }

    // MARK: - Starten

    /// Startet einen Timer aus dem Eingabefeld. `false`, wenn die Eingabe nicht erkannt wurde.
    @discardableResult
    func startFromInput(now: Date = Date()) -> Bool {
        guard let parsed = TimerInputParser.parse(input, now: now) else { return false }
        add(IslandTimer(
            id: UUID(),
            label: parsed.label,
            endDate: parsed.endDate,
            totalDuration: parsed.duration,
            isClockTime: parsed.isClockTime,
            pausedRemaining: nil,
            finishedAt: nil
        ))
        input = ""
        return true
    }

    func start(duration: TimeInterval, label: String? = nil) {
        add(IslandTimer(
            id: UUID(),
            label: label,
            endDate: Date().addingTimeInterval(duration),
            totalDuration: duration,
            isClockTime: false,
            pausedRemaining: nil,
            finishedAt: nil
        ))
    }

    private func add(_ timer: IslandTimer) {
        timers.append(timer)
        sortTimers()
        persist()
        updateTicker()
    }

    // MARK: - Steuern

    func pause(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }), timers[index].isRunning else { return }
        timers[index].pausedRemaining = timers[index].remaining(at: Date())
        persist()
        updateTicker()
    }

    func resume(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }),
              let remaining = timers[index].pausedRemaining else { return }
        timers[index].endDate = Date().addingTimeInterval(remaining)
        timers[index].pausedRemaining = nil
        sortTimers()
        persist()
        updateTicker()
    }

    /// Entfernt einen Timer (laufend oder abgelaufen).
    func remove(_ id: UUID) {
        timers.removeAll { $0.id == id }
        stopRinging(id)
        persist()
        updateTicker()
    }

    func removeAll() {
        timers.removeAll()
        stopRingingAll()
        persist()
        updateTicker()
    }

    /// Abgelaufenen Timer um ein paar Minuten verlängern.
    func snooze(_ id: UUID, minutes: Int = 5) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let duration = TimeInterval(minutes * 60)
        timers[index].endDate = Date().addingTimeInterval(duration)
        timers[index].totalDuration = duration
        timers[index].isClockTime = false
        timers[index].finishedAt = nil
        timers[index].pausedRemaining = nil
        stopRinging(id)
        sortTimers()
        persist()
        updateTicker()
    }

    /// Klingeln beenden und abgelaufene Timer entfernen.
    func dismissRinging() {
        let ids = ringingIDs
        timers.removeAll { ids.contains($0.id) }
        stopRingingAll()
        persist()
        updateTicker()
    }

    // MARK: - Ablauf

    private func updateTicker() {
        let needsTicker = timers.contains(where: \.isRunning) || isRinging
        if needsTicker, ticker == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else if !needsTicker {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func tick() {
        let now = Date()
        var changed = false
        for index in timers.indices where timers[index].isRunning && timers[index].endDate <= now {
            timers[index].finishedAt = now
            ring(timers[index].id, at: now)
            changed = true
        }
        // Klingeln nach einer Weile von selbst beenden; der Timer bleibt als "Abgelaufen" stehen.
        for (id, since) in ringingSince where now.timeIntervalSince(since) > maxRingDuration {
            stopRinging(id)
        }
        if changed { persist() }
        updateTicker()
    }

    private func ring(_ id: UUID, at date: Date) {
        ringingIDs.insert(id)
        ringingSince[id] = date
        updateAlarm()
    }

    private func stopRinging(_ id: UUID) {
        ringingIDs.remove(id)
        ringingSince[id] = nil
        updateAlarm()
    }

    private func stopRingingAll() {
        ringingIDs.removeAll()
        ringingSince.removeAll()
        updateAlarm()
    }

    private func updateAlarm() {
        if isRinging, settings.timerSound {
            guard alarmTimer == nil else { return }
            playAlarm()
            let timer = Timer(timeInterval: 1.6, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.playAlarm() }
            }
            RunLoop.main.add(timer, forMode: .common)
            alarmTimer = timer
        } else {
            alarmTimer?.invalidate()
            alarmTimer = nil
        }
    }

    private func playAlarm() {
        (NSSound(named: NSSound.Name("Glass"))?.copy() as? NSSound)?.play()
    }

    /// Timer, die abgelaufen sind, während die App nicht lief: kurz danach noch klingeln, sonst nur markieren.
    private func catchUpAfterLaunch() {
        let now = Date()
        var changed = false
        for index in timers.indices where timers[index].isRunning && timers[index].endDate <= now {
            timers[index].finishedAt = timers[index].endDate
            if now.timeIntervalSince(timers[index].endDate) < 120 {
                ring(timers[index].id, at: now)
            }
            changed = true
        }
        if changed { persist() }
    }

    private func sortTimers() {
        timers.sort { lhs, rhs in
            if lhs.isFinished != rhs.isFinished { return lhs.isFinished }
            return lhs.remaining(at: Date()) < rhs.remaining(at: Date())
        }
    }

    // MARK: - Persistenz

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.timersFile) else { return }
        do {
            timers = try JSONDecoder().decode([IslandTimer].self, from: data)
        } catch {
            Log.app.error("Timers unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(timers)
            try data.write(to: AppPaths.timersFile, options: .atomic)
        } catch {
            Log.app.error("Saving timers failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    #if DEBUG
    /// Beispieldaten für `DebugSnapshots` (ohne Ton).
    func debugAddSamples() {
        let now = Date()
        timers = [
            IslandTimer(id: UUID(), label: "Wäsche", endDate: now.addingTimeInterval(-5), totalDuration: 2700,
                        isClockTime: false, pausedRemaining: nil, finishedAt: now.addingTimeInterval(-5)),
            IslandTimer(id: UUID(), label: "Pizza", endDate: now.addingTimeInterval(9 * 60 + 41), totalDuration: 720,
                        isClockTime: false, pausedRemaining: nil, finishedAt: nil),
            IslandTimer(id: UUID(), label: nil, endDate: now.addingTimeInterval(2 * 3600), totalDuration: 7200,
                        isClockTime: true, pausedRemaining: nil, finishedAt: nil),
            IslandTimer(id: UUID(), label: "Tee", endDate: now.addingTimeInterval(130), totalDuration: 180,
                        isClockTime: false, pausedRemaining: 130, finishedAt: nil),
        ]
        if let first = timers.first { ringingIDs = [first.id] }
        input = "Anruf @17:30"
    }
    #endif
}
