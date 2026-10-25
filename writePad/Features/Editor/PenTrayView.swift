import SwiftUI

struct PenTrayView: View {
    @Bindable var state: PenTrayState

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(state.favorites.presets.enumerated()), id: \.element.id) { index, preset in
                    Button {
                        state.select(.pen(preset.id))
                    } label: {
                        Image(systemName: preset.ink == .marker ? "highlighter" : "pencil.tip")
                            .foregroundStyle(Color(uiColor: preset.color.uiColor))
                            .frame(width: 44, height: 44)
                            .background(.background, in: .rect(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(state.selection == .pen(preset.id) ? Color.accentColor : .secondary, lineWidth: 2)
                            }
                    }
                    .accessibilityLabel("Favorite Pen \(index + 1)")
                    .accessibilityValue("\(preset.ink.rawValue), \(preset.width.formatted()) points")
                    .accessibilityAddTraits(state.selection == .pen(preset.id) ? .isSelected : [])
                }
                toolButton("Eraser", symbol: "eraser", selection: .eraser)
                toolButton("Lasso", symbol: "lasso", selection: .lasso)
                Button { state.showsSettings = true } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Pen Settings")
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(.bar)
        .popover(isPresented: $state.showsSettings) { PenPresetSettings(state: state) }
    }

    private func toolButton(_ title: String, symbol: String, selection: PenTrayState.Selection) -> some View {
        Button { state.select(selection) } label: {
            Image(systemName: symbol).frame(width: 44, height: 44)
                .background(state.selection == selection ? Color.accentColor.opacity(0.15) : .clear,
                            in: .rect(cornerRadius: 8))
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(state.selection == selection ? .isSelected : [])
    }
}

private struct PenPresetSettings: View {
    @Bindable var state: PenTrayState

    var body: some View {
        NavigationStack {
            Form {
                Picker("Ink", selection: field(\.ink)) {
                    ForEach(PenPreset.Ink.allCases, id: \.self) { ink in Text(ink.rawValue.capitalized).tag(ink) }
                }
                ColorPicker("Pen Color", selection: Binding(
                    get: { Color(uiColor: state.selectedPreset.color.uiColor) },
                    set: { color in
                        var preset = state.selectedPreset
                        preset.color = PenPreset.RGBA(UIColor(color))
                        state.favorites.update(preset)
                    }
                ))
                Text("Width: \(state.selectedPreset.width.formatted()) pt")
                Slider(value: field(\.width), in: 0.5...30, step: 0.5)
                    .accessibilityLabel("Pen Width")
                Button("Add Favorite", systemImage: "plus") {
                    if let id = state.favorites.add() { state.select(.pen(id)) }
                }
                .disabled(state.favorites.presets.count >= 8)
                Button("Remove Favorite", systemImage: "trash", role: .destructive) {
                    state.favorites.remove(state.selectedPreset.id)
                }
                .disabled(state.favorites.presets.count <= 1)
            }
            .navigationTitle("Pen Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { state.showsSettings = false } }
            }
        }
        .frame(minWidth: 320, idealWidth: 380, minHeight: 440)
    }

    private func field<Value>(_ keyPath: WritableKeyPath<PenPreset, Value>) -> Binding<Value> {
        Binding(get: { state.selectedPreset[keyPath: keyPath] }, set: { value in
            var preset = state.selectedPreset
            preset[keyPath: keyPath] = value
            state.favorites.update(preset)
        })
    }
}
