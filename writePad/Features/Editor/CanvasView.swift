import PencilKit
import SwiftUI

/// Lets SwiftUI toolbar buttons reach the underlying `PKCanvasView`.
@MainActor
final class CanvasController {
    weak var canvasView: PKCanvasView?
    /// The PDF reader: its page canvases come and go with scrolling, but it stays in the window.
    weak var pdfView: UIView?

    private var undoManager: UndoManager? { pdfView?.undoManager ?? canvasView?.undoManager }

    func undo() { undoManager?.undo() }
    func redo() { undoManager?.redo() }
}

struct CanvasView: UIViewRepresentable {
    let viewModel: EditorViewModel
    let controller: CanvasController

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> NotebookCanvasView {
        let canvas = NotebookCanvasView()
        canvas.delegate = context.coordinator
        controller.canvasView = canvas
        context.coordinator.snapper = ShapeSnapper(canvas: canvas) { [viewModel] in
            ShapeSnapper.isEnabledInSettings && !viewModel.isReadOnly
        }
        context.coordinator.reload(canvas)

        canvas.tool = viewModel.penTray.tool
        context.coordinator.pencilInteraction = PencilToolInteraction(
            canvas: canvas, state: viewModel.penTray
        ) { [viewModel, weak canvas] in
            canvas?.window?.isKeyWindow == true && !viewModel.isReadOnly && !viewModel.isEditingItems
        }
        // The canvas must be in a window before it can become first responder.
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: NotebookCanvasView, context: Context) {
        canvas.drawingPolicy = viewModel.allowsFingerDrawing ? .anyInput : .pencilOnly
        // Read-only notebooks still scroll and zoom; they just can't be drawn on.
        canvas.drawingGestureRecognizer.isEnabled = !viewModel.isReadOnly && !viewModel.isEditingItems
        let coordinator = context.coordinator
        if coordinator.structureVersion != viewModel.structureVersion {
            coordinator.reload(canvas)
        }
        canvas.itemsOverlay.configure(viewModel: viewModel, pages: viewModel.pages.enumerated().map {
            ($0.element.id, canvas.layout.frame(ofPage: $0.offset))
        })
        canvas.tool = viewModel.penTray.tool
        if !viewModel.isReadOnly, !viewModel.isEditingItems, canvas.window != nil { canvas.becomeFirstResponder() }
        if let request = viewModel.scrollRequest, request.id != coordinator.handledScrollRequestID {
            coordinator.handledScrollRequestID = request.id
            canvas.scrollToPage(request.pageIndex, animated: true)
        }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var pencilInteraction: PencilToolInteraction?
        let viewModel: EditorViewModel
        var structureVersion = -1
        var handledScrollRequestID: UUID?
        var snapper: ShapeSnapper?
        private var isApplyingModel = false

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        /// Rebuilds pages and ink from the model after pages were added, removed, moved or restyled.
        func reload(_ canvas: NotebookCanvasView) {
            isApplyingModel = true
            defer { isApplyingModel = false }
            structureVersion = viewModel.structureVersion
            canvas.setPages(viewModel.pages.map(\.background))
            canvas.drawing = viewModel.combinedDrawing()
            // Undo steps recorded against the old page layout would put strokes on the wrong pages.
            canvas.undoManager?.removeAllActions()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingModel else { return }
            snapper?.drawingDidChange()
            viewModel.drawingDidChange(canvasView.drawing)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? NotebookCanvasView)?.zoomDidChange()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let canvas = scrollView as? NotebookCanvasView, !isApplyingModel else { return }
            viewModel.pageDidBecomeVisible(canvas.visiblePageIndex)
        }
    }
}

/// A `PKCanvasView` showing pages stacked vertically, with paper drawn behind the ink.
final class NotebookCanvasView: PKCanvasView {
    private let pagesView = PagesBackgroundView()
    let itemsOverlay = PageItemsOverlay()
    private(set) var layout = PageLayout(pageCount: 1)
    private var fittedWidth: CGFloat = 0
    private var isFitToWidth = true

    private var fitScale: CGFloat {
        bounds.width / layout.contentSize.width
    }

    var visiblePageIndex: Int {
        layout.pageIndex(atY: (contentOffset.y + bounds.height / 2) / zoomScale)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Paper is always white; keep ink colors from being inverted in dark mode.
        overrideUserInterfaceStyle = .light
        backgroundColor = .clear
        isOpaque = false
        alwaysBounceVertical = true
        pagesView.layer.anchorPoint = .zero
        insertSubview(pagesView, at: 0)
        itemsOverlay.layer.anchorPoint = .zero
        addSubview(itemsOverlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // PencilKit exposes its own accessibility container instead of custom subviews.
    override var accessibilityElements: [Any]? {
        get {
            let ink = super.accessibilityElements ?? subviews.filter { $0 !== itemsOverlay }
            return ink + itemsOverlay.subviews
        }
        set { super.accessibilityElements = newValue }
    }

    func setPages(_ backgrounds: [PageBackground]) {
        layout = PageLayout(pageCount: backgrounds.count)
        pagesView.configure(layout: layout, backgrounds: backgrounds)
        updateContentGeometry()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        if bounds.width != fittedWidth {
            fittedWidth = bounds.width
            minimumZoomScale = fitScale * 0.5
            maximumZoomScale = fitScale * 5
            if isFitToWidth { zoomScale = fitScale }
        }
        updateContentGeometry()
    }

    func zoomDidChange() {
        isFitToWidth = abs(zoomScale - fitScale) < 0.01
        updateContentGeometry()
    }

    private func updateContentGeometry() {
        let size = CGSize(width: layout.contentSize.width * zoomScale, height: layout.contentSize.height * zoomScale)
        if contentSize != size { contentSize = size }
        pagesView.bounds = CGRect(origin: .zero, size: layout.contentSize)
        pagesView.center = .zero
        pagesView.transform = CGAffineTransform(scaleX: zoomScale, y: zoomScale)
        itemsOverlay.bounds = CGRect(origin: .zero, size: layout.contentSize)
        itemsOverlay.center = .zero
        itemsOverlay.transform = CGAffineTransform(scaleX: zoomScale, y: zoomScale)
        bringSubviewToFront(itemsOverlay)
        // Center the pages horizontally when zoomed out narrower than the screen.
        let inset = max(0, (bounds.width - size.width) / 2)
        if contentInset.left != inset {
            contentInset.left = inset
            contentInset.right = inset
        }
    }

    func scrollToPage(_ index: Int, animated: Bool) {
        guard index < layout.pageCount else { return }
        let top = layout.frame(ofPage: index).minY - PageLayout.spacing / 2
        let maxY = max(-adjustedContentInset.top, contentSize.height - bounds.height + adjustedContentInset.bottom)
        let y = min(max(top * zoomScale - adjustedContentInset.top, -adjustedContentInset.top), maxY)
        setContentOffset(CGPoint(x: contentOffset.x, y: y), animated: animated)
    }
}

/// White pages with their paper pattern, laid out in unzoomed canvas coordinates.
/// Uses vector layers so lines stay sharp at any zoom.
private final class PagesBackgroundView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(layout: PageLayout, backgrounds: [PageBackground]) {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        for (index, background) in backgrounds.enumerated() {
            let page = CALayer()
            page.frame = layout.frame(ofPage: index)
            page.backgroundColor = UIColor.white.cgColor
            page.shadowColor = UIColor.black.cgColor
            page.shadowOpacity = 0.12
            page.shadowRadius = 4
            page.shadowOffset = CGSize(width: 0, height: 1)
            page.shadowPath = CGPath(rect: page.bounds, transform: nil)

            let pattern = CAShapeLayer()
            pattern.frame = page.bounds
            pattern.path = PageBackgroundRenderer.patternPath(for: background, size: page.bounds.size)
            if PageBackgroundRenderer.isFilled(background) {
                pattern.fillColor = PageBackgroundRenderer.lineColor.cgColor
            } else {
                pattern.fillColor = nil
                pattern.strokeColor = PageBackgroundRenderer.lineColor.cgColor
                pattern.lineWidth = PageBackgroundRenderer.lineWidth(for: background)
            }
            page.addSublayer(pattern)
            layer.addSublayer(page)
        }
    }
}
