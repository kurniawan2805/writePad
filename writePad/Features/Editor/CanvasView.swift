import PencilKit
import SwiftUI

/// Lets SwiftUI toolbar buttons reach the underlying `PKCanvasView`.
@MainActor
final class CanvasController {
    fileprivate weak var canvasView: PKCanvasView?

    func undo() { canvasView?.undoManager?.undo() }
    func redo() { canvasView?.undoManager?.redo() }
}

struct CanvasView: UIViewRepresentable {
    let initialDrawing: PKDrawing
    let allowsFingerDrawing: Bool
    let controller: CanvasController
    let onDrawingChange: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChange: onDrawingChange)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = initialDrawing
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .systemBackground
        canvas.isOpaque = true
        canvas.alwaysBounceVertical = true
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 4
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        controller.canvasView = canvas

        let toolPicker = context.coordinator.toolPicker
        toolPicker.addObserver(canvas)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        // The canvas must be in a window before it can become first responder.
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        context.coordinator.onDrawingChange = onDrawingChange
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker.removeObserver(canvas)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        var onDrawingChange: (PKDrawing) -> Void

        init(onDrawingChange: @escaping (PKDrawing) -> Void) {
            self.onDrawingChange = onDrawingChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChange(canvasView.drawing)
        }
    }
}
