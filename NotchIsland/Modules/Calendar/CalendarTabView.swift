import SwiftUI

/// Kalender-Tab: nächster Termin mit Countdown links, Liste für heute und morgen rechts.
struct CalendarTabView: View {
    @EnvironmentObject private var calendar: CalendarStore

    var body: some View {
        switch calendar.access {
        case .notDetermined:
            permissionView(
                title: "Kalenderzugriff erlauben",
                detail: "NotchIsland zeigt deine Termine von heute und morgen.",
                button: "Zugriff erlauben"
            ) { calendar.requestAccess() }
        case .denied:
            permissionView(
                title: "Kein Zugriff auf deine Kalender",
                detail: "Erlaube den Zugriff unter Datenschutz & Sicherheit → Kalender.",
                button: "Systemeinstellungen öffnen"
            ) { CalendarStore.openPrivacySettings() }
        case .granted:
            content
        }
    }

    private var content: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            HStack(alignment: .top, spacing: 14) {
                NextEventCard(event: calendar.nextTimedEvent, now: context.date)
                    .frame(width: 210)
                    .frame(maxHeight: .infinity)

                if calendar.events.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 22, weight: .medium))
                        Text("Keine weiteren Termine heute und morgen")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            section("Heute", events: calendar.todayEvents, now: context.date)
                            section("Morgen", events: calendar.tomorrowEvents, now: context.date)
                        }
                        .padding(.bottom, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, events: [CalendarEvent], now: Date) -> some View {
        if !events.isEmpty {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.horizontal, 8)
                .padding(.top, 4)
            ForEach(events) { event in
                CalendarEventRow(event: event, now: now)
            }
        }
    }

    private func permissionView(title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button(button, action: action)
                .buttonStyle(IslandPillButtonStyle())
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Karte mit dem nächsten Termin und großem Countdown.
private struct NextEventCard: View {
    let event: CalendarEvent?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let event {
                Text(event.isOngoing(at: now) ? "JETZT" : "ALS NÄCHSTES")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(event.color)
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                Text(CalendarEventRow.timeRange(event))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer(minLength: 4)
                Text(event.countdown(from: now))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let meeting = event.meeting {
                    JoinMeetingButton(meeting: meeting)
                        .padding(.top, 2)
                }
            } else {
                Text("HEUTE")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.4))
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                Spacer()
                Text("Nichts mehr geplant")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill((event?.color ?? Color.white).opacity(0.12))
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { event?.openInCalendar() }
    }
}

struct CalendarEventRow: View {
    let event: CalendarEvent
    let now: Date
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(event.isOngoing(at: now) ? 1 : 0.9))
                    .lineLimit(1)
                Text([Self.timeRange(event), event.location].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let meeting = event.meeting {
                JoinMeetingButton(meeting: meeting)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.08 : 0))
        }
        .contentShape(Rectangle())
        .onTapGesture { event.openInCalendar() }
        .onHover { hovering = $0 }
        .help("In Kalender öffnen")
    }

    static func timeRange(_ event: CalendarEvent) -> String {
        if event.isAllDay { return "Ganztägig" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

struct JoinMeetingButton: View {
    let meeting: MeetingLink

    var body: some View {
        Button {
            NSWorkspace.shared.open(meeting.url)
        } label: {
            Label("Beitreten", systemImage: "video.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.green.opacity(0.85)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(meeting.service.rawValue)-Meeting beitreten")
    }
}

struct CalendarHeaderActions: View {
    var body: some View {
        HeaderIconButton(systemImage: "calendar", help: "Kalender öffnen") {
            CalendarStore.openCalendarApp()
        }
    }
}

// MARK: - Live-Aktivität

/// Zugeklappt, links: Kalenderfarbe und Titel des anstehenden Termins.
struct CompactCalendarLeading: View {
    @EnvironmentObject private var calendar: CalendarStore

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(calendar.alertEvent?.color ?? Color.accentColor)
                .frame(width: 7, height: 7)
            Text(calendar.alertEvent?.title ?? "Termin")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Zugeklappt, rechts: Countdown bis zum Beginn.
struct CompactCalendarTrailing: View {
    @EnvironmentObject private var calendar: CalendarStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            HStack(spacing: 4) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(calendar.alertEvent.map { $0.countdown(from: context.date) } ?? "")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(calendar.alertEvent?.color ?? Color.accentColor)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}
