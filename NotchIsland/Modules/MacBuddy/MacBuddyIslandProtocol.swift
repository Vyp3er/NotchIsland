// MacBuddy ↔ NotchIsland – gemeinsames Protokoll (Version 1)
//
// Diese Datei ist absichtlich ohne Abhängigkeiten (nur Foundation) und wird unverändert
// in NotchIsland kopiert (NotchIslandIntegration/MacBuddyIslandProtocol.swift).
// Ein Test in MacBuddy prüft, dass beide Kopien identisch sind.
//
// Transport: DistributedNotificationCenter. Die Nutzdaten stehen als JSON-String im
// `object` der Notification (userInfo wird nicht verwendet, damit auch Apps in einer
// Sandbox die Nachrichten empfangen können). Alle Nachrichten tragen das Feld "v".

import Foundation

public enum MacBuddyIsland {
    public static let protocolVersion = 1

    /// Notification-Namen.
    public enum Name {
        // MacBuddy → NotchIsland
        public static let status = Notification.Name("de.vincentschmitt.MacBuddy.island.status")
        public static let result = Notification.Name("de.vincentschmitt.MacBuddy.island.result")
        public static let confirmationRequest = Notification.Name("de.vincentschmitt.MacBuddy.island.confirmationRequest")
        public static let confirmationResolved = Notification.Name("de.vincentschmitt.MacBuddy.island.confirmationResolved")
        public static let ping = Notification.Name("de.vincentschmitt.MacBuddy.island.ping")
        // NotchIsland → MacBuddy
        public static let command = Notification.Name("de.vincentschmitt.NotchIsland.macbuddy.command")
        public static let hello = Notification.Name("de.vincentschmitt.NotchIsland.macbuddy.hello")
    }

    public enum State: String, Codable, Sendable {
        case idle
        case listening
        case thinking
        case working
        case awaitingConfirmation
        case done
        case failed
        case cancelled
    }

    /// Laufender Status (kompakte Anzeige neben der Notch, mit Not-Aus-Button).
    public struct StatusMessage: Codable, Equatable, Sendable {
        public var v: Int
        public var session: String
        public var state: State
        public var title: String
        public var detail: String?
        /// 0…1, falls bekannt (z. B. Routinen-Fortschritt).
        public var progress: Double?
        public var canStop: Bool
        public var timestamp: Date

        public init(session: String, state: State, title: String, detail: String? = nil, progress: Double? = nil,
                    canStop: Bool, timestamp: Date = Date()) {
            v = MacBuddyIsland.protocolVersion
            self.session = session
            self.state = state
            self.title = title
            self.detail = detail
            self.progress = progress
            self.canStop = canStop
            self.timestamp = timestamp
        }
    }

    /// Ergebnis einer Anfrage (kurz anzeigen, dann ausblenden).
    public struct ResultMessage: Codable, Equatable, Sendable {
        public var v: Int
        public var session: String
        public var success: Bool
        public var title: String
        public var text: String
        public var timestamp: Date

        public init(session: String, success: Bool, title: String, text: String, timestamp: Date = Date()) {
            v = MacBuddyIsland.protocolVersion
            self.session = session
            self.success = success
            self.title = title
            self.text = text
            self.timestamp = timestamp
        }
    }

    /// Bestätigungsanfrage für eine riskante Aktion.
    public struct ConfirmationRequest: Codable, Equatable, Sendable {
        public var v: Int
        public var id: String
        public var title: String
        public var detail: String
        public var category: String
        public var confirmLabel: String
        /// false = NotchIsland darf nur anzeigen und „Ablehnen“ anbieten (Bestätigen nur im MacBuddy-Panel).
        public var allowsApproval: Bool
        public var timestamp: Date

        public init(id: String, title: String, detail: String, category: String, confirmLabel: String,
                    allowsApproval: Bool, timestamp: Date = Date()) {
            v = MacBuddyIsland.protocolVersion
            self.id = id
            self.title = title
            self.detail = detail
            self.category = category
            self.confirmLabel = confirmLabel
            self.allowsApproval = allowsApproval
            self.timestamp = timestamp
        }
    }

    /// Die Bestätigung wurde beantwortet (egal wo) – Anzeige entfernen.
    public struct ConfirmationResolved: Codable, Equatable, Sendable {
        public var v: Int
        public var id: String
        public var approved: Bool

        public init(id: String, approved: Bool) {
            v = MacBuddyIsland.protocolVersion
            self.id = id
            self.approved = approved
        }
    }

    /// Befehl von NotchIsland an MacBuddy.
    public struct Command: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            /// Not-Aus: bricht alles sofort ab.
            case stop
            case approve
            case deny
            /// MacBuddy-Panel anzeigen.
            case open
        }

        public var v: Int
        public var command: Kind
        /// Bei approve/deny: id der ConfirmationRequest.
        public var id: String?

        public init(command: Kind, id: String? = nil) {
            v = MacBuddyIsland.protocolVersion
            self.command = command
            self.id = id
        }
    }

    /// NotchIsland meldet sich (beim Start und als Antwort auf `ping`).
    public struct Hello: Codable, Equatable, Sendable {
        public var v: Int
        public var app: String
        public var version: String

        public init(app: String = "NotchIsland", version: String) {
            v = MacBuddyIsland.protocolVersion
            self.app = app
            self.version = version
        }
    }

    // MARK: Kodierung

    public static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from object: Any?) -> T? {
        guard let string = object as? String, let data = string.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    /// Sendet eine Nachricht an alle Zuhörer.
    public static func post<T: Encodable>(_ name: Notification.Name, _ value: T) {
        guard let payload = encode(value) else { return }
        DistributedNotificationCenter.default().postNotificationName(name, object: payload, userInfo: nil, deliverImmediately: true)
    }
}
