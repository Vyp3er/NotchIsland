import AppKit

/// Langlebige Drag-Quelle für das Herausziehen aus der Ablage.
/// Sie lebt im Store, damit der Drag auch weiterläuft, wenn die Island zuklappt.
final class ShelfDragSource: NSObject, NSDraggingSource {
    var operationMask: () -> NSDragOperation = { .copy }
    var onEnded: (NSDragOperation) -> Void = { _ in }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Zurück in die eigene Island ziehen ist kein Ziel.
        context == .outsideApplication ? operationMask() : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onEnded(operation)
    }
}
