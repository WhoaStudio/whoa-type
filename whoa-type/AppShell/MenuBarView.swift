import SwiftUI

struct MenuBarView: View {
    @Bindable var coordinator: AppCoordinator

    private let appName = "Whoa Type"
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(appName).font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("Key sounds", isOn: $coordinator.settings.soundEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.green)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Sound")
                Slider(value: $coordinator.settings.volume, in: 0 ... 1) {
                    Text("Playback volume")
                }
                .tint(.primary)
                .accessibilityValue(Text(coordinator.settings.volume, format: .percent.precision(.fractionLength(0))))
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Switches")
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(coordinator.packs) { pack in
                                packRow(pack).id(pack.id)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(coordinator.packs.count) * 32, 256))
                    .onAppear { proxy.scrollTo(coordinator.settings.selectedPackID, anchor: .center) }
                }
                if coordinator.state != .ready && coordinator.state != .soundOff || coordinator.previewing != nil || coordinator.loading {
                    Text(coordinator.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            Text("Version \(version)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Button("\(appName) Settings…") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                coordinator.showSettings()
            }
            .keyboardShortcut(",")
            .buttonStyle(MenuRowStyle())
            Divider()
            Button("Quit \(appName)") { coordinator.quit() }
                .keyboardShortcut("q")
                .buttonStyle(MenuRowStyle())
        }
        .padding(16)
        .frame(width: 300)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func packRow(_ pack: SoundPack) -> some View {
        let selected = coordinator.settings.selectedPackID == pack.id
        return Button { coordinator.select(pack.id) } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(packColor(pack.name).gradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.black.opacity(0.15), lineWidth: 1)
                    }
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    }
                    .frame(width: 23, height: 23)
                    .accessibilityHidden(true)
                Text(pack.name)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(MenuRowStyle())
        .onHover { hovering in
            if hovering { coordinator.preview(pack.id) }
        }
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Presentation-only colors; pack identities and audio manifests stay untouched.
    private func packColor(_ name: String) -> Color {
        let rgb: UInt32 = switch name {
        case "Keychron Q3 Blue": 0x2684FF
        case "Amber": 0xC88B25
        case "Birch": 0xB8A585
        case "Cedar": 0x985B45
        case "Dune": 0xC4A06A
        case "Ember": 0xD15A38
        case "Flint": 0x717B86
        case "Granite": 0x85838D
        case "Hazel": 0x9A774A
        case "Ivory": 0xC9BB91
        case "Jade": 0x409B7A
        case "Kelp": 0x587647
        case "Linen": 0xB8AD9A
        case "Maple": 0xBD7540
        case "Nimbus": 0x98A8BF
        case "Onyx": 0x454751
        case "Pebble": 0x93928B
        case "Quartz": 0xBD9CB7
        case "Reed": 0x9C9A58
        case "Slate": 0x5C7187
        case "Terra": 0xB76853
        case "Umber": 0x7D5945
        case "Velvet": 0x85548F
        case "Willow": 0x8C9C74
        case "Zephyr": 0x75ABB5
        case "Acorn": 0x94704D
        case "Bamboo": 0xA7AB52
        case "Copper": 0xB87853
        case "Drift": 0xA99C8D
        case "Elm": 0x72835A
        case "Fern": 0x57946B
        case "Grove": 0x416E56
        case "Honey": 0xD5A239
        case "Indigo": 0x5D61AC
        case "Juniper": 0x4C8987
        case "Larch": 0xA1A049
        case "Moss": 0x748647
        case "Nutmeg": 0xA2765D
        case "Opal": 0x91B7BF
        default: 0x808080
        }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }
}

private struct MenuRowStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .background(.primary.opacity(isEnabled && (hovered || configuration.isPressed) ? 0.08 : 0),
                        in: RoundedRectangle(cornerRadius: 5))
            .onHover { hovered = $0 }
    }
}
