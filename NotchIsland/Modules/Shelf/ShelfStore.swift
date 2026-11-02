import AppKit
import Quartz

/// Stellt der Ablage das Island-Fenster bereit (für QuickLook).
@MainActor
protocol ShelfPresentationHost: AnyObject {
    var islandWindow: IslandPanel { get }
    func collapseIsland()
}

/// Inhalt der Ablage: Hinzufügen, Entfernen, Auswahl, Herausziehen und Persistenz.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    /// Elemente, deren Datei verschoben oder gelöscht wurde.
    @Published private(set) var invalidIDs: Set<UUID> = []
    @Published private(set) var selection: Set<UUID> = []
    /// Während ein Drag aus der Ablage läuft, bleibt der Inhalt der Island geladen.
    @Published private(set) var isDraggingOut = false

    weak var presentationHost: ShelfPresentationHost?

    private let settings: AppSettings
    private let dragSource = ShelfDragSource()
    private let quickLook = QuickLookController()
    private var selectionAnchor: UUID?
    private var validationTimer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
        load()
        removeOrphanedFiles()
        revalidate()
    }

    // MARK: - Drops

    func canAccept(_ info: NSDraggingInfo) -> Bool {
        if info.draggingSource is ShelfDragSource { return false }
        return ShelfDropReader.hasContent(info.draggingPasteboard)
    }

    @discardableResult
    func accept(_ info: NSDraggingInfo) -> Bool {
        guard canAccept(info) else { return false }
        return ShelfDropReader.read(info.draggingPasteboard) { [weak self] result in
            self?.add(result)
        }
    }

    private func add(_ result: ShelfDropReader.Result) {
        let newItems: [ShelfItem]
        switch result {
        case .references(let urls):
            newItems = urls
                .filter { url in !items.contains(where: { $0.path == url.path }) }
                .map { ShelfItem(url: $0, storage: .reference) }
        case .owned(let url):
            newItems = [ShelfItem(url: url, storage: .owned)]
        }
        guard !newItems.isEmpty else { return }
        // Neueste Elemente vorne, damit sie sofort sichtbar sind.
        items.insert(contentsOf: newItems, at: 0)
        persist()
        revalidate()
    }

    // MARK: - Entfernen

    func remove(ids: [UUID], deferOwnedFileDeletion: Bool = false) {
        let idSet = Set(ids)
        let removed = items.filter { idSet.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { idSet.contains($0.id) }
        selection.subtract(idSet)
        for item in removed where item.storage == .owned {
            // Nach einem Drag nicht sofort löschen: Browser lesen Upload-Dateien oft erst später.
            deleteOwnedFile(of: item, after: deferOwnedFileDeletion ? 300 : 0)
        }
        persist()
        revalidate()
    }

    func removeAll() {
        remove(ids: items.map(\.id))
    }

    private func deleteOwnedFile(of item: ShelfItem, after delay: TimeInterval) {
        let directory = item.url.deletingLastPathComponent().standardizedFileURL
        let root = AppPaths.shelfFilesDirectory.standardizedFileURL.path + "/"
        // Nur eigene Unterordner in Application Support löschen.
        guard directory.path.hasPrefix(root) else { return }
        let delete = { try? FileManager.default.removeItem(at: directory) }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { delete() }
        } else {
            _ = delete()
        }
    }

    /// Eigene Dateien ohne zugehöriges Element (z. B. nach einem Absturz) aufräumen.
    private func removeOrphanedFiles() {
        let root = AppPaths.shelfFilesDirectory
        let referenced = Set(
            items.filter { $0.storage == .owned }
                .map { $0.url.deletingLastPathComponent().standardizedFileURL.path }
        )
        let contents = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for directory in contents where !referenced.contains(directory.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - Gültigkeit

    func revalidate() {
        let invalid = Set(items.filter { !FileManager.default.fileExists(atPath: $0.path) }.map(\.id))
        if invalid != invalidIDs { invalidIDs = invalid }
    }

    /// Während die Ablage sichtbar ist, regelmäßig prüfen, ob Dateien verschoben/gelöscht wurden.
    func setVisible(_ visible: Bool) {
        if visible {
            revalidate()
            guard validationTimer == nil else { return }
            let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.revalidate() }
            }
            RunLoop.main.add(timer, forMode: .common)
            validationTimer = timer
        } else {
            validationTimer?.invalidate()
            validationTimer = nil
        }
    }

    // MARK: - Auswahl

    func click(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            selectionAnchor = id
        } else if modifiers.contains(.shift),
                  let anchor = selectionAnchor,
                  let from = items.firstIndex(where: { $0.id == anchor }),
                  let to = items.firstIndex(where: { $0.id == id }) {
            selection = Set(items[min(from, to)...max(from, to)].map(\.id))
        } else {
            selection = [id]
            selectionAnchor = id
        }
    }

    func clearSelection() {
        selection = []
        selectionAnchor = nil
    }

    /// Ist das angeklickte Element Teil der Auswahl, gilt eine Aktion für die ganze Auswahl.
    func targets(for id: UUID) -> [ShelfItem] {
        if selection.contains(id) {
            return items.filter { selection.contains($0.id) }
        }
        return items.filter { $0.id == id }
    }

    private func validURLs(of items: [ShelfItem]) -> [URL] {
        items.filter { !invalidIDs.contains($0.id) }.map(\.url)
    }

    // MARK: - Herausziehen

    func beginDrag(from view: NSView, event: NSEvent, anchor id: UUID) {
        if !selection.contains(id) {
            selection = [id]
            selectionAnchor = id
        }
        revalidate()
        let dragged = targets(for: id).filter { !invalidIDs.contains($0.id) }
        guard !dragged.isEmpty else { return }

        let size: CGFloat = 54
        let location = view.convert(event.locationInWindow, from: nil)
        let draggingItems = dragged.enumerated().map { index, item -> NSDraggingItem in
            let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            let image = ThumbnailCache.shared.cachedThumbnail(for: item.url, size: 108)
                ?? NSWorkspace.shared.icon(forFile: item.path)
            let offset = CGFloat(min(index, 4)) * 5
            draggingItem.setDraggingFrame(
                NSRect(x: location.x - size / 2 + offset, y: location.y - size / 2 - offset, width: size, height: size),
                contents: image
            )
            return draggingItem
        }

        let ids = dragged.map(\.id)
        let onlyReferences = dragged.allSatisfy { $0.storage == .reference }
        dragSource.operationMask = {
            // Standard ist Kopieren (das Original bleibt, wo es ist). Mit ⌘ werden Dateien verschoben.
            if onlyReferences, NSEvent.modifierFlags.contains(.command) { return .move }
            return [.copy, .link]
        }
        dragSource.onEnded = { [weak self] operation in
            self?.dragEnded(ids: ids, operation: operation)
        }

        isDraggingOut = true
        let session = view.beginDraggingSession(with: draggingItems, event: event, source: dragSource)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    private func dragEnded(ids: [UUID], operation: NSDragOperation) {
        isDraggingOut = false
        guard !operation.isEmpty else { return }
        if settings.removeAfterDragOut {
            remove(ids: ids, deferOwnedFileDeletion: true)
        } else if operation.contains(.move) {
            followMovedFiles(ids: ids)
        }
        revalidate()
    }

    /// Nach ⌘-Drag: neuen Ort der verschobenen Datei über das Lesezeichen finden.
    private func followMovedFiles(ids: [UUID]) {
        var changed = false
        for index in items.indices where ids.contains(items[index].id) {
            guard !FileManager.default.fileExists(atPath: items[index].path),
                  let bookmark = items[index].bookmark else { continue }
            var stale = false
            guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: resolved.path) else { continue }
            items[index].path = resolved.path
            items[index].displayName = resolved.lastPathComponent
            items[index].bookmark = try? resolved.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            changed = true
        }
        if changed { persist() }
    }

    // MARK: - Aktionen

    func open(_ id: UUID) {
        for url in validURLs(of: targets(for: id)) {
            NSWorkspace.shared.open(url)
        }
    }

    func revealInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func showQuickLook(_ urls: [URL]) {
        guard !urls.isEmpty, let host = presentationHost, let panel = QLPreviewPanel.shared() else { return }
        quickLook.urls = urls
        let window = host.islandWindow
        window.previewController = quickLook
        window.allowsKey = true
        NSApp.activate()
        window.makeKey()
        window.makeMain()
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func contextMenu(for id: UUID) -> NSMenu {
        if !selection.contains(id) {
            selection = [id]
            selectionAnchor = id
        }
        revalidate()
        let targets = targets(for: id)
        let urls = validURLs(of: targets)
        let suffix = targets.count > 1 ? " (\(targets.count))" : ""

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem(title: "Öffnen", systemImage: "arrow.up.forward.app", enabled: !urls.isEmpty) { [weak self] in
            self?.open(id)
        })
        menu.addItem(ClosureMenuItem(title: "Im Finder zeigen", systemImage: "folder", enabled: !urls.isEmpty) { [weak self] in
            self?.revealInFinder(urls)
        })
        menu.addItem(ClosureMenuItem(title: "QuickLook", systemImage: "eye", enabled: !urls.isEmpty) { [weak self] in
            self?.showQuickLook(urls)
        })
        if !urls.isEmpty {
            menu.addItem(NSSharingServicePicker(items: urls).standardShareMenuItem)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Aus Ablage entfernen\(suffix)", systemImage: "xmark.circle") { [weak self] in
            self?.remove(ids: targets.map(\.id))
        })
        return menu
    }

    #if DEBUG
    func debugAddSamples() {
        guard items.isEmpty else { return }
        let samples = [
            "/System/Applications/Calculator.app",
            "/System/Library/CoreServices/Finder.app",
            "/etc/hosts",
            NSHomeDirectory() + "/Desktop",
        ]
        add(.references(samples.map { URL(fileURLWithPath: $0) }))
        add(.references([URL(fileURLWithPath: "/tmp/notchisland-missing-file.pdf")]))
        if let first = items.first { selection = [first.id] }
    }
    #endif

    // MARK: - Persistenz

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.shelfIndexFile) else { return }
        do {
            items = try JSONDecoder().decode([ShelfItem].self, from: data)
        } catch {
            Log.shelf.error("Shelf index unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: AppPaths.shelfIndexFile, options: .atomic)
        } catch {
            Log.shelf.error("Saving shelf failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
