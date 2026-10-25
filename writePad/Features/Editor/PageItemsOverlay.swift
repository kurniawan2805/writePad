import UIKit

/// Item views only intercept their own rectangles, leaving empty paper available for scrolling.
final class PageItemsOverlay: UIView {
    func configure(viewModel: EditorViewModel, pages: [(UUID, CGRect)]) {
        let active = Set(pages.flatMap { viewModel.pageItems[$0.0] ?? [] }.map(\.id))
        for view in subviews {
            if let item = view as? PageItemView, !active.contains(item.item.id) { item.removeFromSuperview() }
        }
        for (pageID, pageFrame) in pages {
            for item in viewModel.pageItems[pageID] ?? [] {
                let itemView = subviews.compactMap { $0 as? PageItemView }.first { $0.item.id == item.id } ?? PageItemView()
                if itemView.superview == nil { addSubview(itemView) }
                itemView.configure(item: item, pageID: pageID, pageFrame: pageFrame, viewModel: viewModel)
                bringSubviewToFront(itemView)
            }
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

final class PageItemView: UIView {
    private(set) var item = PageItem(frame: .zero, content: .text("", fontSize: 24))
    private var pageID = UUID()
    private var pageFrame = CGRect.zero
    private weak var viewModel: EditorViewModel?
    private var original: PageItem?
    private var resizing = false
    private var selected = false
    private var assets: [UUID: Data] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        overrideUserInterfaceStyle = .light
        isAccessibilityElement = true
        accessibilityTraits = .button
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectItem)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(item: PageItem, pageID: UUID, pageFrame: CGRect, viewModel: EditorViewModel) {
        guard original == nil else { return }
        self.item = item
        self.pageID = pageID
        self.pageFrame = pageFrame
        self.viewModel = viewModel
        assets = viewModel.imageAssets
        selected = viewModel.selectedItemID == item.id && viewModel.isEditingItems
        isUserInteractionEnabled = viewModel.isEditingItems && !viewModel.isReadOnly
        accessibilityTraits = isUserInteractionEnabled ? .button : .staticText
        accessibilityIdentifier = "Page Item \(item.id)"
        switch item.content {
        case let .text(text, _): accessibilityLabel = "Text Box: \(text)"
        case .image: accessibilityLabel = "Page Image"
        }
        accessibilityHint = "Drag to move. Drag the bottom right corner to resize. Use Items to edit or delete."
        updateFrame()
    }

    private func updateFrame() {
        frame = item.frame.offsetBy(dx: pageFrame.minX, dy: pageFrame.minY)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        var local = item
        local.frame.origin = .zero
        PageItemRenderer.draw([local], assets: assets, in: context)
        if selected {
            UIColor.systemBlue.setStroke()
            context.setLineWidth(2)
            context.stroke(bounds.insetBy(dx: 1, dy: 1))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: bounds.width - 14, y: bounds.height - 14, width: 14, height: 14))
        }
    }

    override func accessibilityActivate() -> Bool {
        guard isUserInteractionEnabled else { return false }
        selectItem()
        return true
    }

    @objc private func selectItem() {
        viewModel?.selectedItemID = item.id
        if let index = viewModel?.pages.firstIndex(where: { $0.id == pageID }) { viewModel?.pageDidBecomeVisible(index) }
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let viewModel, !viewModel.isReadOnly else { return }
        switch gesture.state {
        case .began:
            original = item
            let point = gesture.location(in: self)
            resizing = point.x > bounds.width - 28 && point.y > bounds.height - 28
            selectItem()
            selected = true
        case .changed, .ended:
            guard let original, let parent = superview else { return }
            let delta = gesture.translation(in: parent)
            item = original
            if resizing {
                item.frame.size.width += delta.x
                item.frame.size.height += delta.y
            } else {
                item.frame.origin.x += delta.x
                item.frame.origin.y += delta.y
            }
            item = item.fitted(to: pageFrame.size)
            updateFrame()
            if gesture.state == .ended {
                self.original = nil
                viewModel.updateItem(item, on: pageID)
            }
        case .cancelled, .failed:
            if let original { item = original; updateFrame() }
            original = nil
        default: break
        }
    }
}
