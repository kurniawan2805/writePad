import PDFKit
import PencilKit
import SwiftUI

struct PDFCanvasView: UIViewRepresentable {
    let viewModel: EditorViewModel
    let pdf: PDFNotebook
    let controller: CanvasController

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel, pdf: pdf, controller: controller) }

    func makeUIView(context: Context) -> PDFView {
        let view = ItemPDFView()
        view.itemElements = { [weak coordinator = context.coordinator] in
            coordinator?.overlays.values.flatMap { $0.itemsOverlay.subviews } ?? []
        }
        view.accessibilityIdentifier = "PDF Reader"
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displayBox = .cropBox
        view.autoScales = true
        view.backgroundColor = .secondarySystemBackground
        view.pageOverlayViewProvider = context.coordinator
        view.document = pdf.document
        context.coordinator.view = view
        pdf.view = view
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged),
                                               name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.isInMarkupMode = pdf.isDrawing || viewModel.isEditingItems
        let coordinator = context.coordinator
        if coordinator.structureVersion != viewModel.structureVersion {
            coordinator.clearOverlays()
            view.document = nil
            view.document = pdf.document
            coordinator.scrollRequestID = nil
            coordinator.structureVersion = viewModel.structureVersion
        }
        for (id, overlay) in coordinator.overlays {
            overlay.itemsOverlay.configure(viewModel: viewModel, pages: [(id, CGRect(origin: .zero, size: viewModel.pageSize(for: id)))])
            overlay.canvas.isUserInteractionEnabled = pdf.isDrawing && !viewModel.isReadOnly && !viewModel.isEditingItems
            overlay.canvas.drawingPolicy = viewModel.allowsFingerDrawing ? .anyInput : .pencilOnly
            overlay.canvas.tool = viewModel.penTray.tool
        }
        if pdf.isDrawing && !viewModel.isEditingItems {
            coordinator.activateCurrentCanvas()
        } else {
            coordinator.deactivateCanvas()
        }
        if let request = viewModel.scrollRequest, request.id != coordinator.scrollRequestID,
           let page = pdf.document.page(at: request.pageIndex) {
            coordinator.scrollRequestID = request.id
            DispatchQueue.main.async { [weak view] in
                guard let view, coordinator.scrollRequestID == request.id else { return }
                view.layoutDocumentView()
                view.go(to: page)
            }
        }
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.clearOverlays()
        NotificationCenter.default.removeObserver(coordinator)
        view.pageOverlayViewProvider = nil
        coordinator.pdf.view = nil
    }

    @MainActor
    final class Coordinator: NSObject, @MainActor PDFPageOverlayViewProvider, PKCanvasViewDelegate {
        let viewModel: EditorViewModel
        let pdf: PDFNotebook
        let controller: CanvasController
        weak var view: PDFView?
        var overlays: [UUID: PDFPageCanvas] = [:]
        var structureVersion = -1
        var scrollRequestID: UUID?

        init(viewModel: EditorViewModel, pdf: PDFNotebook, controller: CanvasController) {
            self.viewModel = viewModel
            self.pdf = pdf
            self.controller = controller
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            guard let id = pdf.pageID(for: page) else { return nil }
            if let overlay = overlays[id] { return overlay }
            let overlay = PDFPageCanvas(size: PDFPageCanvas.displaySize(for: page))
            overlay.canvas.drawing = viewModel.drawing(forPage: id)
            overlay.canvas.delegate = self
            overlay.canvas.isUserInteractionEnabled = pdf.isDrawing && !viewModel.isReadOnly && !viewModel.isEditingItems
            overlay.canvas.drawingPolicy = viewModel.allowsFingerDrawing ? .anyInput : .pencilOnly
            overlay.canvas.tool = viewModel.penTray.tool
            overlay.canvas.accessibilityIdentifier = "PDF Ink Page \((pdf.pages.firstIndex { $0.id == id } ?? 0) + 1)"
            overlay.pencilInteraction = PencilToolInteraction(
                canvas: overlay.canvas, state: viewModel.penTray
            ) { [viewModel, pdf, weak overlay, weak controller] in
                guard let canvas = overlay?.canvas else { return false }
                return controller?.canvasView === canvas && canvas.window?.isKeyWindow == true
                    && pdf.isDrawing && !viewModel.isReadOnly && !viewModel.isEditingItems
            }
            overlay.snapper = ShapeSnapper(canvas: overlay.canvas) { [viewModel] in
                ShapeSnapper.isEnabledInSettings && !viewModel.isReadOnly
            }
            overlay.itemsOverlay.configure(viewModel: viewModel, pages: [(id, CGRect(origin: .zero, size: viewModel.pageSize(for: id)))])
            overlays[id] = overlay
            return overlay
        }

        func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
            if pdf.isDrawing && !viewModel.isEditingItems { activateCurrentCanvas() }
        }

        func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
            guard let overlay = overlayView as? PDFPageCanvas,
                  let id = overlays.first(where: { $0.value === overlay })?.key else { return }
            viewModel.drawingDidChange(overlay.canvas.drawing, pageID: id)
            overlay.canvas.resignFirstResponder()
            overlays[id] = nil
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let (id, overlay) = overlays.first(where: { $0.value.canvas === canvasView }) else { return }
            overlay.snapper?.drawingDidChange()
            viewModel.drawingDidChange(canvasView.drawing, pageID: id)
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            controller.canvasView = canvasView
        }

        @objc func pageChanged() {
            guard let page = view?.currentPage else { return }
            let index = pdf.document.index(for: page)
            guard viewModel.pages.indices.contains(index) else { return }
            viewModel.pageDidBecomeVisible(index)
            if pdf.isDrawing && !viewModel.isEditingItems { activateCurrentCanvas() }
        }

        func activateCurrentCanvas() {
            guard let page = view?.currentPage, let id = pdf.pageID(for: page), let canvas = overlays[id]?.canvas else { return }
            if controller.canvasView !== canvas {
                deactivateCanvas()
                controller.canvasView = canvas
            }
            canvas.tool = viewModel.penTray.tool
            if canvas.window != nil { canvas.becomeFirstResponder() }
        }

        func deactivateCanvas() {
            if let canvas = controller.canvasView {
                canvas.resignFirstResponder()
            }
        }

        func clearOverlays() {
            deactivateCanvas()
            overlays = [:]
            controller.canvasView = nil
        }
    }
}

final class PDFPageCanvas: UIView {
    let canvas = PKCanvasView()
    let itemsOverlay = PageItemsOverlay()
    var snapper: ShapeSnapper?
    var pencilInteraction: PencilToolInteraction?
    private let pageSize: CGSize

    init(size: CGSize) {
        pageSize = size
        super.init(frame: CGRect(origin: .zero, size: size))
        backgroundColor = .clear
        canvas.overrideUserInterfaceStyle = .light
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.contentSize = size
        canvas.pinchGestureRecognizer?.isEnabled = false
        addSubview(canvas)
        addSubview(itemsOverlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep ink in displayed page points while PDFKit resizes the overlay for zoom.
        canvas.transform = .identity
        canvas.bounds = CGRect(origin: .zero, size: pageSize)
        canvas.center = CGPoint(x: bounds.midX, y: bounds.midY)
        canvas.transform = CGAffineTransform(scaleX: bounds.width / pageSize.width, y: bounds.height / pageSize.height)
        itemsOverlay.transform = .identity
        itemsOverlay.bounds = CGRect(origin: .zero, size: pageSize)
        itemsOverlay.center = CGPoint(x: bounds.midX, y: bounds.midY)
        itemsOverlay.transform = canvas.transform
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let hit = itemsOverlay.hitTest(convert(point, to: itemsOverlay), with: event) { return hit }
        guard canvas.isUserInteractionEnabled else { return nil }
        return super.hitTest(point, with: event)
    }

    nonisolated static func displaySize(for page: PDFPage) -> CGSize {
        let size = page.bounds(for: .cropBox).size
        return page.rotation % 180 == 0 ? size : CGSize(width: size.height, height: size.width)
    }
}

private final class ItemPDFView: PDFView {
    var itemElements: (() -> [UIView])?

    // PDFKit page accessibility omits provider overlays.
    override var accessibilityElements: [Any]? {
        get { (super.accessibilityElements ?? subviews) + (itemElements?() ?? []) }
        set { super.accessibilityElements = newValue }
    }
}
