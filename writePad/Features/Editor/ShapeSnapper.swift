import PencilKit
import UIKit.UIGestureRecognizerSubclass

/// Draw a stroke and hold the pen still before lifting it: the stroke is replaced by the clean shape it resembles
/// (see `ShapeRecognizer`), keeping its ink. The snap is its own undo step, so undo brings the hand-drawn stroke back.
@MainActor
final class ShapeSnapper {
    static let enabledKey = "shapeSnapEnabled"
    /// How long the pen must stay still at the end of a stroke.
    static let holdDuration: TimeInterval = 0.45

    static var isEnabledInSettings: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private weak var canvas: PKCanvasView?
    private let isEnabled: () -> Bool
    private var strokeCountAtTouchDown = 0
    /// Set when a held stroke ended before PencilKit added it to the drawing.
    private var pendingSnap: (expectedCount: Int, deadline: Date)?

    init(canvas: PKCanvasView, isEnabled: @escaping () -> Bool = { ShapeSnapper.isEnabledInSettings }) {
        self.canvas = canvas
        self.isEnabled = isEnabled
        let watcher = StrokeHoldRecognizer()
        watcher.onBegin = { [weak self] in self?.strokeBegan() }
        watcher.onEnd = { [weak self] held in self?.strokeEnded(heldStill: held) }
        canvas.addGestureRecognizer(watcher)
    }

    /// Call from `canvasViewDrawingDidChange`: PencilKit may add the stroke before or after the touch ends.
    func drawingDidChange() {
        guard let pending = pendingSnap, let canvas, Date() < pending.deadline,
              canvas.drawing.strokes.count == pending.expectedCount else { return }
        pendingSnap = nil
        snapLastStroke(expectedCount: pending.expectedCount)
    }

    func strokeBegan() {
        pendingSnap = nil
        strokeCountAtTouchDown = canvas?.drawing.strokes.count ?? 0
    }

    func strokeEnded(heldStill: TimeInterval) {
        guard heldStill >= Self.holdDuration, isEnabled(), let canvas else { return }
        let expected = strokeCountAtTouchDown + 1
        if canvas.drawing.strokes.count == expected {
            snapLastStroke(expectedCount: expected)
        } else {
            pendingSnap = (expected, Date().addingTimeInterval(1))
        }
    }

    private func snapLastStroke(expectedCount: Int) {
        // Not while PencilKit is still delivering the change that added the stroke.
        DispatchQueue.main.async { [weak self] in
            guard let canvas = self?.canvas, canvas.drawing.strokes.count == expectedCount,
                  let stroke = canvas.drawing.strokes.last, let snapped = Self.snapped(stroke) else { return }
            var drawing = canvas.drawing
            drawing.strokes[drawing.strokes.count - 1] = snapped
            Self.replace(canvas.drawing, with: drawing, on: canvas)
        }
    }

    /// Sets the drawing and registers the way back, with redo, as one undo step.
    private static func replace(_ old: PKDrawing, with new: PKDrawing, on canvas: PKCanvasView) {
        canvas.drawing = new
        canvas.undoManager?.registerUndo(withTarget: canvas) { canvas in
            Self.replace(new, with: old, on: canvas)
        }
        canvas.undoManager?.setActionName("Shape")
    }

    /// The stroke redrawn as its recognized shape with the same ink and transform, or nil when it isn't one.
    static func snapped(_ stroke: PKStroke) -> PKStroke? {
        let points = stroke.path.map(\.location)
        guard let shape = ShapeRecognizer.recognize(points) else { return nil }
        // The middle point stands for the stroke's pressure and tilt; a clean shape gets an even line.
        let template = stroke.path[stroke.path.count / 2]
        let outline = ShapeRecognizer.outline(of: shape).enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(index) * 0.004, size: template.size,
                          opacity: template.opacity, force: template.force, azimuth: template.azimuth,
                          altitude: template.altitude)
        }
        return PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: outline, creationDate: stroke.path.creationDate),
                        transform: stroke.transform, mask: stroke.mask)
    }
}

/// Watches the touches on a canvas without ever recognizing, so PencilKit keeps drawing, and reports how long the
/// single touch stayed still before it lifted.
final class StrokeHoldRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// Movement smaller than this, in screen points, still counts as holding still.
    static let stillTolerance: CGFloat = 3

    var onBegin: (() -> Void)?
    var onEnd: ((TimeInterval) -> Void)?
    private var lastMove: (point: CGPoint, time: TimeInterval)?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // Two fingers scroll or zoom; only single-touch strokes can be held.
        guard let touch = touches.first, event.allTouches?.count == 1 else {
            state = .failed
            return
        }
        lastMove = (touch.location(in: nil), touch.timestamp)
        onBegin?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let last = lastMove else { return }
        if event.allTouches?.count ?? 1 > 1 {
            state = .failed
            return
        }
        let point = touch.location(in: nil)
        if hypot(point.x - last.point.x, point.y - last.point.y) > Self.stillTolerance {
            lastMove = (point, touch.timestamp)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let last = lastMove {
            onEnd?(touch.timestamp - last.time)
        }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func reset() {
        super.reset()
        lastMove = nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
