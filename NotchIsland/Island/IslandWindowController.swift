import AppKit
import Combine
import SwiftUI

/// Verwaltet die beiden Panels, Hover-Erkennung, Drag-Hover und das Auf-/Zuklappen.
@MainActor
final class IslandWindowController: NSObject {
    private let environment: AppEnvironment
    private var model: IslandViewModel { environment.island }
    private var settings: AppSettings { environment.settings }

    private let islandPanel: IslandPanel
    private let hotspotPanel: HotspotPanel
    private let containerView: IslandContainerView
    private let hotspotView: HotspotView

    private var cancellables = Set<AnyCancellable>()
    private var trackingTimer: Timer?
    private var outsideSince: TimeInterval?
    private var pendingOpen: DispatchWorkItem?
    private var menuTrackingDepth = 0

    /// Platz um die Island herum für den Schatten.
    private let shadowPadding: CGFloat = 40
    /// Toleranz um die geöffnete Island, bevor sie als "verlassen" gilt.
    private let exitTolerance: CGFloat = 6

    init(environment: AppEnvironment) {
        self.environment = environment
        islandPanel = IslandPanel(contentRect: .zero)
        hotspotPanel = HotspotPanel(contentRect: .zero)
        containerView = IslandContainerView(frame: .zero)
        hotspotView = HotspotView(frame: .zero)
        super.init()

        let hostingView = IslandHostingView(rootView: AnyView(IslandRootView().withAppEnvironment(environment)))
        hostingView.sizingOptions = []
        containerView.embed(hostingView)
        islandPanel.contentView = containerView
        hotspotPanel.contentView = hotspotView

        environment.shelf.presentationHost = self
        environment.island.collapseHandler = { [weak self] in self?.collapse() }
        environment.island.makeKeyForTextInput = { [weak self] in self?.makeKeyForTextInput() }

        configureHotspot()
        configureIslandDrops()
    }

    func start() {
        relayout()
        islandPanel.orderFrontRegardless()
        hotspotPanel.orderFrontRegardless()
        observe()
    }

    // MARK: - Beobachtung

    private func observe() {
        let center = NotificationCenter.default
        center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.bringToFront() }
            .store(in: &cancellables)

        center.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in self?.menuTrackingDepth += 1 }
            .store(in: &cancellables)

        center.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                menuTrackingDepth = max(0, menuTrackingDepth - 1)
            }
            .store(in: &cancellables)

        settings.$islandSize
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // Erst nach dem Setzen des neuen Werts neu layouten.
                DispatchQueue.main.async { self?.relayout() }
            }
            .store(in: &cancellables)

        Publishers.Merge(settings.$tabOrder.map { _ in () }, settings.$hiddenTabs.map { _ in () })
            .sink { [weak self] _ in DispatchQueue.main.async { self?.model.validateSelection() } }
            .store(in: &cancellables)

        model.$compactActivity
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateHotspotFrame() } }
            .store(in: &cancellables)

        // Tastaturfokus nur im Timer-Tab.
        Publishers.CombineLatest(model.$isExpanded, model.$selectedTab)
            .sink { [weak self] expanded, tab in
                DispatchQueue.main.async { self?.updateTextInput(enabled: expanded && tab == .timer) }
            }
            .store(in: &cancellables)

        center.publisher(for: NSWindow.didResignKeyNotification, object: islandPanel)
            .sink { [weak self] _ in self?.environment.timers.isEditingInput = false }
            .store(in: &cancellables)

        // Neu abgelaufener Timer: Island aufklappen.
        environment.timers.$ringingIDs
            .scan((Set<UUID>(), Set<UUID>())) { last, current in (last.1, current) }
            .sink { [weak self] previous, current in
                guard !current.subtracting(previous).isEmpty else { return }
                DispatchQueue.main.async { self?.presentRingingTimer() }
            }
            .store(in: &cancellables)

        // Neue Bestätigungsanfrage von MacBuddy: Island aufklappen und offen halten.
        environment.macBuddy.$confirmation
            .map { $0?.id }
            .removeDuplicates()
            .sink { [weak self] id in
                guard id != nil else { return }
                DispatchQueue.main.async { self?.presentMacBuddyConfirmation() }
            }
            .store(in: &cancellables)
    }

    /// Ein Timer ist abgelaufen: im Timer-Tab aufklappen (bleibt offen, solange er klingelt).
    private func presentRingingTimer() {
        guard settings.timerAutoExpand,
              settings.isVisible(.timer),
              environment.timers.isRinging else { return }
        if model.isExpanded {
            model.select(.timer)
        } else {
            expand(tab: .timer)
        }
    }

    // MARK: - Texteingabe

    /// Nur mit offenem Timer-Tab darf das Panel Tastatureingaben annehmen.
    private func updateTextInput(enabled: Bool) {
        islandPanel.acceptsTextInput = enabled
        guard !enabled, islandPanel.isKeyWindow, islandPanel.previewController == nil else { return }
        // Tastaturfokus an die zuvor aktive App zurückgeben.
        islandPanel.orderOut(nil)
        islandPanel.orderFrontRegardless()
        hotspotPanel.orderFrontRegardless()
    }

    /// Key-Window werden, ohne die App zu aktivieren (nicht aktivierendes Panel).
    private func makeKeyForTextInput() {
        guard model.isExpanded else { return }
        islandPanel.acceptsTextInput = true
        islandPanel.makeKey()
    }

    private func presentMacBuddyConfirmation() {
        guard settings.macBuddyAutoExpand,
              settings.isVisible(.macBuddy),
              environment.macBuddy.confirmation != nil else { return }
        if model.isExpanded {
            model.select(.macBuddy)
        } else {
            expand(tab: .macBuddy)
        }
    }

    // MARK: - Layout

    private func relayout() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        model.update(geometry: geometry, expandedSize: settings.islandSize.expandedSize)

        let island = model.expandedFrameSize
        let panelSize = CGSize(width: island.width + 2 * shadowPadding, height: island.height + shadowPadding)
        islandPanel.setFrame(geometry.topAnchoredRect(size: panelSize), display: true)
        updateHotspotFrame()
        bringToFront()
    }

    private func updateHotspotFrame() {
        let frame = model.geometry.topAnchoredRect(size: model.collapsedFrameSize)
        hotspotPanel.setFrame(frame, display: true)
    }

    private func bringToFront() {
        islandPanel.orderFrontRegardless()
        hotspotPanel.orderFrontRegardless()
    }

    /// Rechteck der geöffneten Island in globalen Koordinaten.
    private var expandedIslandRect: CGRect {
        model.geometry.topAnchoredRect(size: model.expandedFrameSize)
    }

    /// Rechteck der geöffneten Island in Koordinaten des Island-Panels.
    private var expandedIslandRectInPanel: CGRect {
        let size = model.expandedFrameSize
        let bounds = containerView.bounds
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.maxY - size.height, width: size.width, height: size.height)
    }

    // MARK: - Hover

    private func configureHotspot() {
        hotspotView.onHoverChanged = { [weak self] inside in
            guard let self else { return }
            updateCompactActionHover()
            model.setPeeking(inside && !model.isPointerOnCompactAction)
            if inside { scheduleOpen() } else { cancelPendingOpen() }
        }
        hotspotView.onMouseMoved = { [weak self] in
            guard let self, !model.isExpanded else { return }
            updateCompactActionHover()
            model.setPeeking(!model.isPointerOnCompactAction)
            // Über dem Not-Aus nicht aufklappen, damit er sich zugeklappt anklicken lässt.
            if model.isPointerOnCompactAction {
                cancelPendingOpen()
            } else if pendingOpen == nil {
                scheduleOpen()
            }
        }
        hotspotView.onClick = { [weak self] in
            guard let self else { return }
            if isOnCompactStop(NSEvent.mouseLocation) {
                environment.macBuddy.stopMacBuddy()
                if settings.hapticFeedback {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                }
                return
            }
            // Klick auf eine Live-Aktivität öffnet deren Tab, sonst den zuletzt genutzten.
            expand(tab: model.compactActivity.tab)
        }
        hotspotView.dropHandlers = DropHandlers(
            update: { [weak self] info, _ in
                guard let self, settings.isVisible(.shelf), environment.shelf.canAccept(info) else { return [] }
                if !model.isExpanded { expand(tab: .shelf) } else { model.select(.shelf) }
                model.isDropTargeted = true
                return .copy
            },
            exited: {},
            perform: { [weak self] info, _ in
                guard let self else { return false }
                model.isDropTargeted = false
                return environment.shelf.accept(info)
            }
        )
    }

    private func scheduleOpen() {
        guard !model.isExpanded, !isOnCompactStop(NSEvent.mouseLocation) else { return }
        cancelPendingOpen()
        let delay = max(0, settings.openDelay)
        if delay < 0.01 {
            expand()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingOpen = nil
            // Nur öffnen, wenn der Zeiger noch über der Notch (und nicht auf dem Not-Aus) ist.
            let location = NSEvent.mouseLocation
            if hotspotPanel.frame.insetBy(dx: -2, dy: -2).contains(location), !isOnCompactStop(location) {
                expand()
            }
        }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingOpen() {
        pendingOpen?.cancel()
        pendingOpen = nil
    }

    /// Rechtes "Ohr" der MacBuddy-Aktivität: dort liegt der Not-Aus, zugeklappt direkt klickbar.
    private func isOnCompactStop(_ point: NSPoint) -> Bool {
        guard !model.isExpanded,
              model.compactActivity == .macBuddy,
              environment.macBuddy.canStop else { return false }
        return hotspotPanel.frame.contains(point) && point.x >= model.geometry.notchRect.maxX
    }

    private func updateCompactActionHover() {
        let onStop = isOnCompactStop(NSEvent.mouseLocation)
        if model.isPointerOnCompactAction != onStop { model.isPointerOnCompactAction = onStop }
    }

    // MARK: - Drops auf die geöffnete Island

    private func configureIslandDrops() {
        containerView.dropHandlers = DropHandlers(
            update: { [weak self] info, point in
                guard let self, model.isExpanded, settings.isVisible(.shelf), environment.shelf.canAccept(info) else {
                    return []
                }
                let inside = expandedIslandRectInPanel.contains(point)
                if inside {
                    model.select(.shelf)
                    outsideSince = nil
                }
                if model.isDropTargeted != inside { model.isDropTargeted = inside }
                return inside ? .copy : []
            },
            exited: { [weak self] in
                guard let self, model.isDropTargeted else { return }
                model.isDropTargeted = false
            },
            perform: { [weak self] info, point in
                guard let self, expandedIslandRectInPanel.contains(point) else { return false }
                model.isDropTargeted = false
                return environment.shelf.accept(info)
            }
        )
    }

    // MARK: - Auf-/Zuklappen

    func expand(tab: IslandTab? = nil) {
        cancelPendingOpen()
        model.isPointerOnCompactAction = false
        let wasExpanded = model.isExpanded
        model.expand(tab: tab)
        islandPanel.ignoresMouseEvents = false
        hotspotPanel.ignoresMouseEvents = true
        outsideSince = nil
        startTracking()
        if !wasExpanded, settings.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func collapse() {
        cancelPendingOpen()
        stopTracking()
        model.collapse()
        islandPanel.ignoresMouseEvents = true
        hotspotPanel.ignoresMouseEvents = false
    }

    private func startTracking() {
        guard trackingTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
        // .common: läuft auch während Drags und offener Kontextmenüs weiter.
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        outsideSince = nil
    }

    /// Prüft, ob der Zeiger die geöffnete Island verlassen hat, und klappt nach der Verzögerung zu.
    private func trackPointer() {
        guard model.isExpanded else {
            stopTracking()
            return
        }
        let location = NSEvent.mouseLocation
        let inside = expandedIslandRect.insetBy(dx: -exitTolerance, dy: -exitTolerance).contains(location)
        if inside || menuTrackingDepth > 0 || environment.keepsIslandOpen {
            outsideSince = nil
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard let since = outsideSince else {
            outsideSince = now
            return
        }
        if now - since >= settings.closeDelay {
            collapse()
        }
    }
}

// MARK: - Darstellung von Systemfenstern (QuickLook)

extension IslandWindowController: ShelfPresentationHost {
    var islandWindow: IslandPanel { islandPanel }

    func collapseIsland() { collapse() }
}
