import SwiftUI

/// Timer-Tab: Eingabe in natürlicher Sprache ("5min", "@17:30", "Pizza 12 min"), Enter startet.
struct TimerTabView: View {
    @EnvironmentObject private var timers: TimerStore
    @EnvironmentObject private var island: IslandViewModel
    @FocusState private var inputFocused: Bool
    @State private var shakes = 0

    var body: some View {
        VStack(spacing: 10) {
            inputField
            if timers.timers.isEmpty {
                presets
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(timers.timers) { timer in
                            TimerCard(timer: timer, isRinging: timers.ringingIDs.contains(timer.id))
                                .frame(width: 156)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: timers.timers.map(\.id))
            }
        }
        .onAppear {
            if island.consumePendingTextFocus() { inputFocused = true }
        }
        .onChange(of: island.textFocusRequest) { _, _ in
            inputFocused = true
        }
        .onChange(of: inputFocused) { _, focused in
            timers.isEditingInput = focused
        }
        .onDisappear {
            timers.isEditingInput = false
        }
    }

    // MARK: - Eingabe

    private var inputField: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.orange)
            TextField(
                "",
                text: $timers.input,
                prompt: Text("5min, 15 Minuten, @17:30 oder Pizza 12 min").foregroundStyle(Color.white.opacity(0.35))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.white)
            .focused($inputFocused)
            .onSubmit(submit)
            .onExitCommand {
                if timers.input.isEmpty { island.requestCollapse() } else { timers.input = "" }
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                preview(now: context.date)
            }

            if !timers.input.isEmpty {
                Button("Start", action: submit)
                    .buttonStyle(IslandPillButtonStyle(tint: .orange))
                    .disabled(TimerInputParser.parse(timers.input) == nil)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(inputFocused ? 0.12 : 0.07))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(inputFocused ? 0.7 : 0), lineWidth: 1)
        }
        .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
        .simultaneousGesture(TapGesture().onEnded { island.focusTextInput() })
        .animation(.easeOut(duration: 0.15), value: inputFocused)
    }

    @ViewBuilder
    private func preview(now: Date) -> some View {
        if let parsed = TimerInputParser.parse(timers.input, now: now) {
            let end = parsed.endDate.formatted(date: .omitted, time: .shortened)
            // Bei Uhrzeiten keine Sekunden anzeigen.
            let duration = parsed.isClockTime ? (parsed.duration / 60).rounded(.up) * 60 : parsed.duration
            Text("bis \(end) · \(TimerFormat.duration(duration))")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.green)
                .lineLimit(1)
                .fixedSize()
        } else if !timers.input.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Nicht erkannt")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.85))
                .fixedSize()
        }
    }

    private func submit() {
        if timers.startFromInput() {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        } else if !timers.input.isEmpty {
            withAnimation(.linear(duration: 0.35)) { shakes += 1 }
        }
    }

    // MARK: - Schnellwahl

    private var presets: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach([1, 3, 5, 10, 15, 25, 60], id: \.self) { minutes in
                    Button(minutes == 60 ? "1 Std" : "\(minutes) Min") {
                        timers.start(duration: TimeInterval(minutes * 60))
                    }
                    .buttonStyle(IslandPillButtonStyle())
                }
            }
            Text("Dauer oder Uhrzeit eintippen und ⏎ drücken – „@“ steht für eine Uhrzeit.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Eine Timer-Karte: Restzeit, Fortschritt, Pause/Fortsetzen/Entfernen bzw. Schlummern/Stopp.
private struct TimerCard: View {
    let timer: IslandTimer
    let isRinging: Bool
    @EnvironmentObject private var timers: TimerStore
    @State private var pulse = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(timer.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if !isRinging {
                        Button {
                            timers.remove(timer.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .help("Timer entfernen")
                    }
                }

                Text(timer.isFinished ? "0:00" : TimerFormat.countdown(timer.remaining(at: now)))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timer.isPaused ? Color.white.opacity(0.45) : (isRinging ? Color.orange : Color.white))
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * timer.progress(at: now))
                    }
                }
                .frame(height: 4)

                Spacer(minLength: 0)

                if timer.isFinished {
                    // Abgelaufen: Hinweis und zwei breite Knöpfe untereinander, damit nichts abgeschnitten wird.
                    Text(footnote)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Button { timers.snooze(timer.id) } label: { Text("+5 Min").frame(maxWidth: .infinity) }
                            .buttonStyle(IslandPillButtonStyle())
                            .help("Um 5 Minuten verlängern")
                        Button { timers.remove(timer.id) } label: { Text(isRinging ? "Stopp" : "OK").frame(maxWidth: .infinity) }
                            .buttonStyle(IslandPillButtonStyle(tint: isRinging ? .orange : nil))
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(footnote)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        controls
                    }
                }
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isRinging ? Color.orange.opacity(pulse ? 0.32 : 0.18) : Color.white.opacity(0.06))
        }
        .onAppear { startPulse() }
        .onChange(of: isRinging) { _, _ in startPulse() }
    }

    private func startPulse() {
        guard isRinging else {
            pulse = false
            return
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
    }

    @ViewBuilder
    private var controls: some View {
        if timer.isPaused {
            circleButton("play.fill", help: "Fortsetzen") { timers.resume(timer.id) }
        } else {
            circleButton("pause.fill", help: "Pausieren") { timers.pause(timer.id) }
        }
    }

    private func circleButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var icon: String {
        if isRinging { return "alarm.waves.left.and.right.fill" }
        if timer.isFinished { return "checkmark.circle.fill" }
        if timer.isPaused { return "pause.circle.fill" }
        return timer.isClockTime ? "clock.fill" : "timer"
    }

    private var tint: Color {
        if isRinging { return .orange }
        if timer.isFinished { return .green }
        if timer.isPaused { return .gray }
        return .orange
    }

    private var footnote: String {
        if let finishedAt = timer.finishedAt {
            return "Abgelaufen \(finishedAt.formatted(date: .omitted, time: .shortened))"
        }
        if timer.isPaused { return "Pausiert" }
        return "bis \(timer.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

/// Kurzes Schütteln bei nicht erkannter Eingabe.
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Kopfzeile: Klingeln beenden bzw. alle Timer entfernen.
struct TimerHeaderActions: View {
    @EnvironmentObject private var timers: TimerStore

    var body: some View {
        if timers.isRinging {
            HeaderIconButton(systemImage: "bell.slash.fill", help: "Klingeln beenden", tint: .orange) {
                timers.dismissRinging()
            }
        } else if !timers.timers.isEmpty {
            Text("\(timers.timers.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.5))
            HeaderIconButton(systemImage: "trash.fill", help: "Alle Timer entfernen") {
                timers.removeAll()
            }
        }
    }
}

// MARK: - Live-Aktivität

/// Zugeklappt, links: Symbol und Name des nächsten (oder klingelnden) Timers.
struct CompactTimerLeading: View {
    @EnvironmentObject private var timers: TimerStore

    var body: some View {
        let timer = timers.ringingTimer ?? timers.nextRunning
        HStack(spacing: 6) {
            Image(systemName: timers.isRinging ? "alarm.waves.left.and.right.fill" : "timer")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.orange)
                .symbolEffect(.pulse, isActive: timers.isRinging)
            Text(timer?.title ?? "Timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Zugeklappt, rechts: Restzeit.
struct CompactTimerTrailing: View {
    @EnvironmentObject private var timers: TimerStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let ringing = timers.isRinging
            let remaining = timers.nextRunning?.remaining(at: context.date) ?? 0
            Text(ringing ? "Abgelaufen" : TimerFormat.countdown(remaining))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ringing ? Color.orange : Color.white)
                .opacity(ringing && Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 0.45 : 1)
                .lineLimit(1)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}
