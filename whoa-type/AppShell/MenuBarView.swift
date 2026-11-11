import SwiftUI

struct MenuBarView: View {
    @Bindable var coordinator: AppCoordinator
    let close: () -> Void
    @State private var hoverPreview: Task<Void, Never>?

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
                            ForEach(Array(coordinator.packs.enumerated()), id: \.element.id) { index, pack in
                                packRow(pack, index: index).id(pack.id)
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
                close()
                coordinator.showSettings()
            }
            .keyboardShortcut(",")
            .buttonStyle(MenuRowStyle())
            Divider()
            CheckForUpdatesButton(updater: coordinator.updater)
                .buttonStyle(MenuRowStyle())
            Button("Quit \(appName)") { coordinator.quit() }
                .keyboardShortcut("q")
                .buttonStyle(MenuRowStyle())
        }
        .padding(16)
        .frame(width: 300)
        .onChange(of: coordinator.settings.disableSwitchPreviewOnHover) { _, disabled in
            if disabled { hoverPreview?.cancel() }
        }
        .onDisappear { hoverPreview?.cancel() }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func packRow(_ pack: SoundPack, index: Int) -> some View {
        let selected = coordinator.settings.selectedPackID == pack.id
        return Button { coordinator.select(pack.id) } label: {
            HStack(spacing: 10) {
                SoundPackBadge(index: index, size: 23)
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
            // Debounce so sweeping the pointer down the list does not queue a load per row.
            hoverPreview?.cancel()
            guard hovering, !coordinator.settings.disableSwitchPreviewOnHover else { return }
            hoverPreview = Task {
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled && !coordinator.settings.disableSwitchPreviewOnHover {
                    coordinator.preview(pack.id)
                }
            }
        }
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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
