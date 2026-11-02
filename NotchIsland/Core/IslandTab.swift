import Foundation

enum IslandTab: String, CaseIterable, Identifiable, Codable {
    case shelf
    case music
    case camera
    case calendar
    case clipboard
    case macBuddy
    case timer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shelf: "Ablage"
        case .music: "Musik"
        case .camera: "Kamera"
        case .calendar: "Kalender"
        case .clipboard: "Zwischenablage"
        case .macBuddy: "MacBuddy"
        case .timer: "Timer"
        }
    }

    var systemImage: String {
        switch self {
        case .shelf: "tray.full.fill"
        case .music: "music.note"
        case .camera: "camera.fill"
        case .calendar: "calendar"
        case .clipboard: "doc.on.clipboard.fill"
        case .macBuddy: "cursorarrow.rays"
        case .timer: "timer"
        }
    }
}
