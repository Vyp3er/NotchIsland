import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "NotchIsland"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let island = Logger(subsystem: subsystem, category: "Island")
    static let shelf = Logger(subsystem: subsystem, category: "Shelf")
    static let music = Logger(subsystem: subsystem, category: "Music")
    static let camera = Logger(subsystem: subsystem, category: "Camera")
    static let calendar = Logger(subsystem: subsystem, category: "Calendar")
    static let clipboard = Logger(subsystem: subsystem, category: "Clipboard")
}
