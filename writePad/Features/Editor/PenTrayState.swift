import Observation
import PencilKit
import UIKit

@MainActor
@Observable
final class PenFavorites {
    static let preferenceKey = "penFavorites.v1"
    static let shared = PenFavorites(defaults: preferenceDefaults)
    private(set) var presets: [PenPreset]
    private let defaults: UserDefaults

    private static var preferenceDefaults: UserDefaults {
        #if DEBUG
        if let namespace = ProcessInfo.processInfo.environment[StorageLocation.namespaceKey] {
            return UserDefaults(suiteName: "writePad.pens.\(namespace)") ?? .standard
        }
        #endif
        return .standard
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.preferenceKey),
           let saved = try? JSONDecoder().decode([PenPreset].self, from: data),
           (1...8).contains(saved.count), Set(saved.map(\.id)).count == saved.count, saved.allSatisfy(\.isValid) {
            presets = saved
        } else {
            presets = [PenPreset(), PenPreset(color: .init(red: 0.1, green: 0.3, blue: 0.8)),
                       PenPreset(ink: .marker, width: 16, color: .init(red: 1, green: 0.8, blue: 0.1))]
        }
    }

    @discardableResult
    func add() -> UUID? {
        guard presets.count < 8 else { return nil }
        let preset = PenPreset()
        presets.append(preset)
        persist()
        return preset.id
    }

    func update(_ preset: PenPreset) {
        guard preset.isValid, let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
        persist()
    }

    func remove(_ id: UUID) {
        guard presets.count > 1 else { return }
        presets.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) { defaults.set(data, forKey: Self.preferenceKey) }
    }
}

@MainActor
@Observable
final class PenTrayState {
    enum Selection: Equatable { case pen(UUID), eraser, lasso }

    let favorites: PenFavorites
    private var chosen: Selection
    private var previous: Selection
    var showsSettings = false

    init(favorites: PenFavorites = .shared) {
        self.favorites = favorites
        let first = Selection.pen(favorites.presets[0].id)
        chosen = first
        previous = .eraser
    }

    var selection: Selection { valid(chosen) }
    var selectedPreset: PenPreset {
        if case let .pen(id) = selection, let preset = favorites.presets.first(where: { $0.id == id }) { return preset }
        return favorites.presets[0]
    }

    var tool: PKTool {
        switch selection {
        case .pen: selectedPreset.tool
        case .eraser: PKEraserTool(.bitmap)
        case .lasso: PKLassoTool()
        }
    }

    func select(_ selection: Selection) {
        let next = valid(selection)
        guard next != self.selection else { return }
        previous = self.selection
        chosen = next
    }

    func perform(_ action: UIPencilPreferredAction) {
        switch action {
        case .switchEraser:
            select(selection == .eraser ? valid(previous) : .eraser)
        case .switchPrevious:
            select(valid(previous))
        case .showColorPalette, .showInkAttributes, .showContextualPalette:
            showsSettings.toggle()
        case .ignore, .runSystemShortcut: break
        @unknown default: break
        }
    }

    private func valid(_ selection: Selection) -> Selection {
        if case let .pen(id) = selection, !favorites.presets.contains(where: { $0.id == id }) {
            return .pen(favorites.presets[0].id)
        }
        return selection
    }
}

@MainActor
final class PencilToolInteraction: NSObject, UIPencilInteractionDelegate {
    let state: PenTrayState
    let isEnabled: () -> Bool

    init(canvas: PKCanvasView, state: PenTrayState, isEnabled: @escaping () -> Bool) {
        self.state = state
        self.isEnabled = isEnabled
        super.init()
        canvas.addInteraction(UIPencilInteraction(delegate: self))
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        if isEnabled() { state.perform(UIPencilInteraction.preferredTapAction) }
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        if isEnabled(), squeeze.phase == .ended { state.perform(UIPencilInteraction.preferredSqueezeAction) }
    }
}
