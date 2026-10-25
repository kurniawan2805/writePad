import Foundation
import PencilKit
import Testing
import UIKit
@testable import writePad

@MainActor
struct PenTrayTests {
    private func favorites() throws -> PenFavorites {
        PenFavorites(defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
    }

    @Test func favoritesRoundTripInkWidthAndRGBA() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let favorites = PenFavorites(defaults: defaults)
        var pen = favorites.presets[1]
        pen.ink = .pencil
        pen.width = 7.5
        pen.color = .init(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        favorites.update(pen)
        let restored = PenFavorites(defaults: defaults)
        #expect(restored.presets == favorites.presets)
        #expect(restored.presets[1].tool.inkType == .pencil)
        #expect(restored.presets[1].tool.width == 7.5)
        #expect(restored.presets[1].tool.color == pen.color.uiColor)
    }

    @Test func capacityAndLastFavoriteAreProtected() throws {
        let favorites = try favorites()
        for _ in 0..<12 { favorites.add() }
        #expect(favorites.presets.count == 8)
        #expect(favorites.add() == nil)
        for preset in favorites.presets { favorites.remove(preset.id) }
        #expect(favorites.presets.count == 1)
    }

    @Test func invalidOrDuplicatePreferencesFallBackWithoutCrashing() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let preset = PenPreset()
        for data in [Data("broken".utf8), try JSONEncoder().encode([PenPreset]()),
                     try JSONEncoder().encode([preset, preset]),
                     try JSONEncoder().encode([PenPreset(width: -3)]),
                     try JSONEncoder().encode([PenPreset(color: .init(red: 5, green: 0, blue: 0))])] {
            defaults.set(data, forKey: PenFavorites.preferenceKey)
            #expect(PenFavorites(defaults: defaults).presets.count == 3)
        }
    }

    @Test func invalidEditsAreRejectedAndDeletedSelectionFallsBack() throws {
        let favorites = try favorites()
        let state = PenTrayState(favorites: favorites)
        let first = favorites.presets[0]
        var invalid = first
        invalid.width = .infinity
        favorites.update(invalid)
        #expect(favorites.presets[0] == first)
        favorites.remove(first.id)
        #expect(state.selection == .pen(favorites.presets[0].id))
        #expect(state.tool is PKInkingTool)
    }

    @Test func pencilActionsSwitchAndRestoreToolsAndRespectDisabledActions() throws {
        let state = PenTrayState(favorites: try favorites())
        let first = state.selection
        state.perform(.switchEraser)
        #expect(state.tool is PKEraserTool)
        state.perform(.switchEraser)
        #expect(state.selection == first)
        state.select(.lasso)
        #expect(state.tool is PKLassoTool)
        state.perform(.switchPrevious)
        #expect(state.selection == first)
        state.perform(.switchPrevious)
        #expect(state.selection == .lasso)
        state.perform(.ignore)
        state.perform(.runSystemShortcut)
        #expect(state.selection == .lasso)
        for action in [UIPencilPreferredAction.showColorPalette, .showInkAttributes, .showContextualPalette] {
            state.showsSettings = false
            state.perform(action)
            #expect(state.showsSettings)
        }
    }

    @Test func sharedFavoritesKeepIndependentActiveTools() throws {
        let favorites = try favorites()
        let left = PenTrayState(favorites: favorites)
        let right = PenTrayState(favorites: favorites)
        left.select(.eraser)
        #expect(right.tool is PKInkingTool)
        var pen = right.selectedPreset
        pen.width = 12
        favorites.update(pen)
        #expect(right.selectedPreset.width == 12)
        #expect(left.selection == .eraser)
    }
}
