import SwiftUI

struct SoundSettingsView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        Toggle("Play key and click sounds", isOn: $coordinator.settings.soundEnabled)
            .toggleStyle(SettingsToggleStyle())
        if coordinator.settings.soundEnabled || coordinator.errorMessage != nil {
            playbackStatus
        }
        VStack(spacing: 10) {
            HStack {
                Text("Playback volume")
                Spacer()
                SettingsBadge(Text(coordinator.settings.volume, format: .percent.precision(.fractionLength(0))))
            }
            Slider(value: $coordinator.settings.volume, in: 0...1) { Text("Playback volume") }
                .labelsHidden()
                .accessibilityValue(Text(coordinator.settings.volume, format: .percent.precision(.fractionLength(0))))
            HStack {
                Text("Previews work when key sounds are off.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Test Key Sound") { coordinator.previewKey() }
                    .disabled(coordinator.packs.isEmpty)
            }
        }
        Picker("Physical keyboard layout", selection: $coordinator.settings.keyboardGeometry) {
            ForEach(KeyboardGeometry.allCases, id: \.self) { geometry in
                Text(geometry.rawValue).tag(geometry)
            }
        }
    }

    private var playbackStatus: some View {
        let state = coordinator.state
        return VStack(alignment: .leading, spacing: 8) {
            Text(state.message).foregroundStyle(.secondary)
            switch state {
            case .permissionRequired:
                Button("Open Input Monitoring…") {
                    coordinator.permission.request()
                    coordinator.permission.openSystemSettings()
                }
            case .captureUnavailable, .audioUnavailable:
                Button("Retry Audio") { coordinator.refresh() }
            case .soundOff, .preparingAudio, .ready:
                EmptyView()
            }
        }
    }
}
