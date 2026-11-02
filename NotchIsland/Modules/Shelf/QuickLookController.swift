import AppKit
import Quartz

/// Datenquelle für das QuickLook-Panel.
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var urls: [URL] = []

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }
}

extension IslandPanel {
    // QuickLook sucht seinen Controller in der Responder-Kette des Key-/Main-Windows.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        previewController != nil
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = previewController
        panel.delegate = previewController
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
        previewController = nil
        allowsKey = false
    }
}
