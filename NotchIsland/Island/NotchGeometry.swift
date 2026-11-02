import AppKit

/// Position und Größe der (echten oder virtuellen) Notch in globalen Bildschirmkoordinaten.
struct NotchGeometry: Equatable {
    /// `NSScreen.frame` des Bildschirms, auf dem die Island liegt.
    let screenFrame: CGRect
    /// Rechteck der Notch (bzw. der virtuellen Notch ohne Kamera-Aussparung).
    let notchRect: CGRect
    let hasNotch: Bool

    var notchSize: CGSize { notchRect.size }

    /// Ohne Bildschirm (sollte nicht vorkommen) eine plausible Standardgröße.
    static let fallback = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 1512 / 2 - 95, y: 982 - 32, width: 190, height: 32),
        hasNotch: false
    )

    init(screenFrame: CGRect, notchRect: CGRect, hasNotch: Bool) {
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.hasNotch = hasNotch
    }

    /// Misst die Notch über Safe-Area und die freien Bereiche links/rechts daneben.
    init(screen: NSScreen) {
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let height = screen.safeAreaInsets.top
            let width = max(frame.width - left.width - right.width, 120)
            let minX = frame.minX + left.width
            self.init(
                screenFrame: frame,
                notchRect: CGRect(x: minX, y: frame.maxY - height, width: width, height: height),
                hasNotch: true
            )
        } else {
            // Kein Notch: virtuelle Notch in Menüleistenhöhe oben mittig.
            let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
            let height = min(max(menuBarHeight > 0 ? menuBarHeight : NSStatusBar.system.thickness, 24), 32)
            let width: CGFloat = 190
            self.init(
                screenFrame: frame,
                notchRect: CGRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height),
                hasNotch: false
            )
        }
    }

    /// Bildschirm mit Notch bevorzugen, sonst der Hauptbildschirm (der mit der Menüleiste).
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
    }

    /// Rechteck einer oben an der Notch hängenden Fläche der Größe `size` (globale Koordinaten).
    func topAnchoredRect(size: CGSize) -> CGRect {
        CGRect(
            x: notchRect.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
