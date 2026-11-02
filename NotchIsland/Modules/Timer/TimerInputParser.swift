import Foundation

/// Erkennt Timer-Eingaben in natürlicher Sprache (Deutsch und Englisch).
///
/// Dauer:    "5min", "15 Minuten", "1h30", "1 Stunde 20", "90s", "1,5 Std", "anderthalb Stunden",
///           "halbe Stunde", "half an hour", "25:00" (Minuten:Sekunden), "10" (= Minuten)
/// Uhrzeit:  "@5pm", "@17:30", "um 17 Uhr", "bis 18.30", "5:30pm" – nur mit "@"/"um"/"bis"/"at"
///           oder "Uhr"/"am"/"pm", damit "25:00" eindeutig eine Dauer bleibt.
/// Name:     Übrige Wörter werden zum Namen, z. B. "Pizza 12 min" oder "Tee in 3 Minuten".
enum TimerInputParser {
    struct Result: Equatable {
        var endDate: Date
        var duration: TimeInterval
        var label: String?
        /// true bei einer Uhrzeit ("@17:30"), false bei einer Dauer ("15 Minuten").
        var isClockTime: Bool
    }

    /// Längster erlaubter Timer.
    static let maximumDuration: TimeInterval = 7 * 24 * 3600

    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> Result? {
        let normalized = input
            .replacingOccurrences(of: "a.m.", with: "am", options: .caseInsensitive)
            .replacingOccurrences(of: "p.m.", with: "pm", options: .caseInsensitive)
        let tokens = tokenize(normalized)
        guard !tokens.isEmpty else { return nil }
        var consumed = Array(repeating: false, count: tokens.count)

        if let end = parseClockTime(tokens, consumed: &consumed, now: now, calendar: calendar) {
            let duration = end.timeIntervalSince(now)
            guard duration > 0, duration <= maximumDuration else { return nil }
            return Result(endDate: end, duration: duration, label: label(tokens, consumed: consumed), isClockTime: true)
        }
        // "@" meint immer eine Uhrzeit; eine ungültige ("@25:00") nicht als Dauer deuten.
        if tokens.contains(.at) { return nil }

        consumed = Array(repeating: false, count: tokens.count)
        guard let duration = parseDuration(tokens, consumed: &consumed),
              duration >= 1, duration <= maximumDuration else { return nil }
        return Result(
            endDate: now.addingTimeInterval(duration),
            duration: duration,
            label: label(tokens, consumed: consumed),
            isClockTime: false
        )
    }

    // MARK: - Zerlegen

    private enum Token: Equatable {
        case number(Double, raw: String)
        /// "25:00" oder "1:30:00"
        case clock([Int])
        case word(String)
        case at
    }

    private static let tokenPattern = try? NSRegularExpression(
        pattern: #"@|\d+(?::\d{1,2}){1,2}|\d+(?:[.,]\d+)?|[\p{L}']+"#
    )

    private static func tokenize(_ text: String) -> [Token] {
        guard let tokenPattern else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return tokenPattern.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let raw = String(text[swiftRange])
            if raw == "@" { return .at }
            if raw.contains(":") {
                let parts = raw.split(separator: ":").compactMap { Int($0) }
                return parts.count >= 2 ? .clock(parts) : nil
            }
            if let first = raw.first, first.isNumber {
                return Double(raw.replacingOccurrences(of: ",", with: ".")).map { .number($0, raw: raw) }
            }
            return .word(raw)
        }
    }

    // MARK: - Uhrzeit

    private static let clockPrefixes: Set<String> = ["um", "bis", "gegen", "at", "until", "till"]
    private static let clockSuffixes: Set<String> = ["uhr", "am", "pm", "o'clock"]

    private static func parseClockTime(_ tokens: [Token], consumed: inout [Bool], now: Date, calendar: Calendar) -> Date? {
        for index in tokens.indices {
            var hasPrefix = false
            switch tokens[index] {
            case .at: hasPrefix = true
            case .word(let word): hasPrefix = clockPrefixes.contains(word.lowercased())
            default: break
            }
            let numberIndex = hasPrefix ? index + 1 : index
            guard numberIndex < tokens.count, let (hour, minute) = hourAndMinute(tokens[numberIndex]) else { continue }

            var suffix: String?
            if numberIndex + 1 < tokens.count, case .word(let word) = tokens[numberIndex + 1] {
                let lower = word.lowercased()
                if clockSuffixes.contains(lower) {
                    suffix = lower
                } else if unitSeconds(lower) != nil {
                    // "um 5 Minuten" ist keine Uhrzeit.
                    continue
                }
            }
            guard hasPrefix || suffix != nil else { continue }

            var hour24 = hour
            switch suffix {
            case "pm":
                guard (1...12).contains(hour) else { continue }
                hour24 = hour == 12 ? 12 : hour + 12
            case "am":
                guard (1...12).contains(hour) else { continue }
                hour24 = hour == 12 ? 0 : hour
            default:
                break
            }
            guard (0...23).contains(hour24), (0...59).contains(minute),
                  var date = calendar.date(bySettingHour: hour24, minute: minute, second: 0, of: now) else { continue }

            if date <= now {
                // "@5" um 14:30 meint 17:00 heute, nicht 5:00 morgen.
                if suffix == nil, (1...11).contains(hour24),
                   let afternoon = calendar.date(byAdding: .hour, value: 12, to: date), afternoon > now {
                    date = afternoon
                } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) {
                    date = tomorrow
                }
            }

            let lastIndex = suffix == nil ? numberIndex : numberIndex + 1
            for consumedIndex in index...lastIndex { consumed[consumedIndex] = true }
            return date
        }
        return nil
    }

    private static func hourAndMinute(_ token: Token) -> (Int, Int)? {
        switch token {
        case .clock(let parts) where parts.count == 2:
            return (parts[0], parts[1])
        case .number(let value, let raw):
            if let separator = raw.firstIndex(where: { $0 == "." || $0 == "," }) {
                // "17.30" / "5,30" → 17:30 / 5:30
                let fraction = raw[raw.index(after: separator)...]
                guard fraction.count == 2, let hour = Int(raw[..<separator]), let minute = Int(fraction) else { return nil }
                return (hour, minute)
            }
            guard value == value.rounded() else { return nil }
            return (Int(value), 0)
        default:
            return nil
        }
    }

    // MARK: - Dauer

    private static let numberWords: [String: Double] = [
        "ein": 1, "eine": 1, "einen": 1, "einer": 1, "one": 1, "a": 1, "an": 1,
        "zwei": 2, "two": 2, "drei": 3, "three": 3, "vier": 4, "four": 4,
        "fünf": 5, "fuenf": 5, "five": 5, "sechs": 6, "six": 6, "sieben": 7, "seven": 7,
        "acht": 8, "eight": 8, "neun": 9, "nine": 9, "zehn": 10, "ten": 10,
        "elf": 11, "eleven": 11, "zwölf": 12, "zwoelf": 12, "twelve": 12,
        "fünfzehn": 15, "fifteen": 15, "zwanzig": 20, "twenty": 20,
        "dreißig": 30, "dreissig": 30, "thirty": 30, "vierzig": 40, "forty": 40,
        "fünfundvierzig": 45, "fünfzig": 50, "fifty": 50, "sechzig": 60, "sixty": 60,
        "halbe": 0.5, "halben": 0.5, "half": 0.5,
        "anderthalb": 1.5, "eineinhalb": 1.5, "zweieinhalb": 2.5,
    ]

    /// Zusammengesetzte Wörter, die schon eine Dauer sind.
    private static let compoundDurations: [String: TimeInterval] = [
        "viertelstunde": 15 * 60,
        "dreiviertelstunde": 45 * 60,
        "halbestunde": 30 * 60,
    ]

    private static func unitSeconds(_ word: String) -> TimeInterval? {
        switch word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "s", "sec", "secs", "second", "seconds", "sek", "sekunde", "sekunden": 1
        case "m", "min", "mins", "minute", "minutes", "minuten", "minütchen": 60
        case "h", "hr", "hrs", "hour", "hours", "std", "stunde", "stunden", "stündchen": 3600
        case "d", "day", "days", "tag", "tage", "tagen": 86400
        default: nil
        }
    }

    private static func parseDuration(_ tokens: [Token], consumed: inout [Bool]) -> TimeInterval? {
        var total: TimeInterval = 0
        var found = false
        var lastUnit: TimeInterval?
        var index = 0

        while index < tokens.count {
            switch tokens[index] {
            case .clock(let parts):
                // "25:00" = 25 Minuten, "1:30:00" = 1,5 Stunden
                if parts.count == 2 {
                    total += TimeInterval(parts[0] * 60 + parts[1])
                } else {
                    total += TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
                }
                consumed[index] = true
                found = true
                lastUnit = nil

            case .number(let value, _):
                if index + 1 < tokens.count, case .word(let word) = tokens[index + 1], let unit = unitSeconds(word) {
                    total += value * unit
                    consumed[index] = true
                    consumed[index + 1] = true
                    lastUnit = unit
                    found = true
                    index += 2
                    continue
                }
                // Zahl ohne Einheit: nach Stunden Minuten ("1h30"), nach Minuten Sekunden, sonst Minuten.
                let unit: TimeInterval
                switch lastUnit {
                case 86400: unit = 3600
                case 3600: unit = 60
                case 60: unit = 1
                default: unit = 60
                }
                total += value * unit
                consumed[index] = true
                lastUnit = unit
                found = true

            case .word(let word):
                let lower = word.lowercased()
                if let compound = compoundDurations[lower] {
                    total += compound
                    consumed[index] = true
                    lastUnit = 60
                    found = true
                } else if let value = numberWords[lower] {
                    var unitIndex = index + 1
                    // "half an hour"
                    if value == 0.5, unitIndex < tokens.count, case .word(let filler) = tokens[unitIndex],
                       ["an", "a"].contains(filler.lowercased()) {
                        unitIndex += 1
                    }
                    if unitIndex < tokens.count, case .word(let unitWord) = tokens[unitIndex], let unit = unitSeconds(unitWord) {
                        total += value * unit
                        for consumedIndex in index...unitIndex { consumed[consumedIndex] = true }
                        lastUnit = unit
                        found = true
                        index = unitIndex + 1
                        continue
                    }
                }

            case .at:
                break
            }
            index += 1
        }
        return found ? total : nil
    }

    // MARK: - Name

    private static let fillerWords: Set<String> = [
        "in", "für", "fur", "for", "timer", "nach", "after", "und", "and", "von", "of", "the",
        "der", "die", "das", "den", "dem", "einen", "ein", "eine", "a", "an", "noch", "bitte", "please",
        "mal", "stelle", "stellen", "set", "start", "starte", "starten", "countdown", "auf",
        "um", "bis", "gegen", "at", "until", "till",
    ]

    private static func label(_ tokens: [Token], consumed: [Bool]) -> String? {
        let words = tokens.indices.compactMap { index -> String? in
            guard !consumed[index], case .word(let word) = tokens[index],
                  !fillerWords.contains(word.lowercased()) else { return nil }
            return word
        }
        let text = words.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return String(text.prefix(40))
    }
}

/// Anzeige von Restzeiten und Dauern.
enum TimerFormat {
    /// "4:59", "1:02:03"
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// "45 Sek", "5 Min 30 Sek", "47 Min", "1 Std 30 Min", "2 Tage 3 Std" (Sekunden nur unter 10 Minuten)
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) Sek" }
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [String] = []
        if days > 0 { parts.append(days == 1 ? "1 Tag" : "\(days) Tage") }
        if hours > 0 { parts.append("\(hours) Std") }
        if minutes > 0 { parts.append("\(minutes) Min") }
        if secs > 0, total < 600 { parts.append("\(secs) Sek") }
        return parts.joined(separator: " ")
    }
}
