import SwiftUI

struct SettingsBadge: View {
    private let text: Text
    private let color: Color

    init(_ text: Text, color: Color = Color(nsColor: .systemBlue)) {
        self.text = text
        self.color = color
    }

    var body: some View {
        text
            .font(.callout.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
    }
}

struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(Color(nsColor: .systemBlue))
    }
}

struct HotkeyKeycaps: View {
    @Binding var modifierChoice: Int
    @Binding var keyChoice: Int
    @Binding var enabled: Bool
    @State private var editingModifiers = false
    @State private var editingKey = false

    private let modifiers = [
        (symbol: "⇧", name: "shift"),
        (symbol: "⌃", name: "control"),
        (symbol: "⌥", name: "option"),
        (symbol: "⌘", name: "command"),
    ]
    private let presets = [[1, 2], [1, 2, 3], [0, 3]]

    private var activeModifiers: [Int] {
        presets[presets.indices.contains(modifierChoice) ? modifierChoice : 0]
    }

    private var keyIndex: Int {
        SoundHotkey.keys.indices.contains(keyChoice) ? keyChoice : 0
    }

    private var keyName: String { SoundHotkey.keys[keyIndex].0 }

    var body: some View {
        HStack(spacing: 7) {
            Button {
                editingModifiers = true
            } label: {
                HStack(spacing: 7) {
                    ForEach(modifiers.indices, id: \.self) { index in
                        let modifier = modifiers[index]
                        keycap(active: enabled && activeModifiers.contains(index)) {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(modifier.symbol).font(.system(size: 17, weight: .medium))
                                Text(modifier.name).font(.system(size: 10, weight: .medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .bottomTrailing)
                        }
                    }
                }
                .contentShape(.rect)
            }
            .accessibilityLabel("Shortcut modifiers")
            .accessibilityValue(activeModifiers.map { modifiers[$0].name }.joined(separator: ", "))
            .help("Choose shortcut modifiers")
            .popover(isPresented: $editingModifiers, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modifiers").font(.headline)
                    ForEach(presets.indices, id: \.self) { index in
                        let label = presets[index].map { modifiers[$0].name }.joined(
                            separator: " + ")
                        choice(label, selected: activeModifiers == presets[index]) {
                            modifierChoice = index
                            editingModifiers = false
                        }
                    }
                }
                .padding(12)
                .frame(minWidth: 190)
            }

            Button {
                editingKey = true
            } label: {
                keycap(active: enabled) {
                    Text(keyName == "Space" ? "space" : keyName)
                        .font(.system(size: keyName == "Space" ? 13 : 21, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .frame(width: keyName == "Space" ? 78 : 58)
            }
            .accessibilityLabel("Shortcut key")
            .accessibilityValue(enabled ? keyName : "Off")
            .help("Choose a shortcut key or turn it off")
            .popover(isPresented: $editingKey, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key").font(.headline)
                    ForEach(SoundHotkey.keys.indices, id: \.self) { index in
                        choice(SoundHotkey.keys[index].0, selected: enabled && keyIndex == index) {
                            if keyChoice != index { keyChoice = index }
                            if !enabled { enabled = true }
                            editingKey = false
                        }
                    }
                    Divider()
                    choice("Off", selected: !enabled) {
                        if enabled { enabled = false }
                        editingKey = false
                    }
                }
                .padding(12)
                .frame(minWidth: 112)
            }
        }
        .buttonStyle(KeycapButtonStyle())
    }

    private func choice(
        _ title: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
        }
        .buttonStyle(.bordered)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func keycap(active: Bool, @ViewBuilder content: () -> some View) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        return content()
            .foregroundStyle(active ? .primary : .secondary)
            .padding(7)
            .frame(height: 48)
            .background {
                shape.fill(.primary.opacity(active ? 0.24 : 0.16)).offset(y: 2)
                shape.fill(
                    Color(nsColor: active ? .controlBackgroundColor : .windowBackgroundColor))
                shape.strokeBorder(.primary.opacity(active ? 0.23 : 0.13))
            }
            .contentShape(shape)
    }
}

private struct KeycapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
            .brightness(configuration.isPressed ? -0.04 : 0)
    }
}

struct SwitchSoundPicker: View {
    let coordinator: AppCoordinator
    @State private var isPresented = false

    private var selectedPack: SoundPack? {
        coordinator.packs.first { $0.id == coordinator.settings.selectedPackID }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("Switch sound").fixedSize()
            Spacer(minLength: 0)
            if let selectedPack {
                Button {
                    coordinator.preview(selectedPack.id)
                } label: {
                    Image(
                        systemName: coordinator.previewing == selectedPack.name
                            ? "waveform" : "speaker.wave.2"
                    )
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview \(selectedPack.name)")
                .help("Preview \(selectedPack.name)")
            }

            Button {
                isPresented = true
            } label: {
                HStack(spacing: 6) {
                    if let selectedPack {
                        SoundPackBadge(
                            index: coordinator.packs.firstIndex { $0.id == selectedPack.id } ?? 0
                        )
                    }
                    Text(selectedPack?.name ?? "Choose a sound")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Switch sound")
            .accessibilityValue(selectedPack?.name ?? "No sound selected")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(Array(coordinator.packs.enumerated()), id: \.element.id) {
                            index, pack in
                            let selected = pack.id == coordinator.settings.selectedPackID
                            Button {
                                coordinator.select(pack.id)
                                isPresented = false
                            } label: {
                                HStack(spacing: 8) {
                                    SoundPackBadge(index: index)
                                    Text(pack.name)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(4)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(8)
                }
                .frame(width: 275, height: 285)
            }
        }
    }

}

struct SoundPackBadge: View {
    let index: Int
    var size: CGFloat = 20

    private var color: Color {
        // The golden angle spaces consecutive hues without cycling through a fixed palette.
        let hue = (0.1 + Double(index) * 0.381966).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.58, brightness: 0.76)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size / 4)
        Image(systemName: "plus")
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .frame(width: size, height: size)
            .background(color.gradient, in: shape)
            .overlay { shape.strokeBorder(.black.opacity(0.14)) }
            .accessibilityHidden(true)
    }
}
