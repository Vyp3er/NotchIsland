import AppKit
import EventKit
import SwiftUI

/// Aufbereiteter Termin für die Island.
struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let eventIdentifier: String?
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let location: String?
    let meeting: MeetingLink?

    init(event: EKEvent) {
        eventIdentifier = event.eventIdentifier
        id = "\(event.eventIdentifier ?? UUID().uuidString)|\(event.startDate.timeIntervalSince1970)"
        title = (event.title?.isEmpty == false ? event.title : nil) ?? "Ohne Titel"
        start = event.startDate
        end = event.endDate
        isAllDay = event.isAllDay
        color = event.calendar.map { Color(nsColor: $0.color) } ?? .accentColor
        location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        meeting = MeetingLink.detect(url: event.url, texts: [event.location, event.notes])
    }

    func isOngoing(at date: Date) -> Bool { start <= date && date < end }

    /// "in 5 Min", "in 1 Std 20 Min", "läuft noch 12 Min".
    func countdown(from date: Date) -> String {
        if isOngoing(at: date) {
            return "läuft noch \(Self.duration(end.timeIntervalSince(date)))"
        }
        return "in \(Self.duration(start.timeIntervalSince(date)))"
    }

    private static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes) Min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) Std" : "\(hours) Std \(rest) Min"
    }

    /// Öffnet den Termin in der Kalender-App.
    func openInCalendar() {
        if let identifier = eventIdentifier,
           let url = URL(string: "ical://ekevent/\(identifier)?method=show&options=more"),
           NSWorkspace.shared.open(url) {
            return
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// Erkannter Link zu einer Videokonferenz.
struct MeetingLink: Equatable {
    enum Service: String {
        case zoom = "Zoom"
        case teams = "Teams"
        case meet = "Meet"
        case webex = "Webex"
    }

    let url: URL
    let service: Service

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func detect(url: URL?, texts: [String?]) -> MeetingLink? {
        if let url, let service = classify(url) { return MeetingLink(url: url, service: service) }
        guard let detector else { return nil }
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, options: [], range: range) {
                if let found = match.url, let service = classify(found) {
                    return MeetingLink(url: found, service: service)
                }
            }
        }
        return nil
    }

    private static func classify(_ url: URL) -> Service? {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "zoommtg" || scheme == "zoomus" { return .zoom }
        if scheme == "msteams" { return .teams }
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return ["/j/", "/my/", "/w/", "/s/"].contains(where: path.hasPrefix) ? .zoom : nil
        }
        if host == "teams.microsoft.com" || host == "teams.live.com" || host.hasSuffix(".teams.microsoft.com") {
            return path.contains("meetup-join") || path.contains("/meet") || path.contains("/l/") ? .teams : nil
        }
        if host == "meet.google.com" {
            return path.count > 1 ? .meet : nil
        }
        if host.hasSuffix(".webex.com") {
            return .webex
        }
        return nil
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
