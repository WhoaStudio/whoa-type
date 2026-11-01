import SwiftUI

struct SoundSettingsView: View {
    @Bindable var settings: SettingsStore
    var body: some View {
        Toggle("Play key and click sounds", isOn: $settings.soundEnabled)
            .toggleStyle(.switch)
        VStack(spacing: 10) {
            HStack {
                Text("Playback volume")
                Spacer()
                Text(settings.volume, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            Slider(value: $settings.volume, in: 0...1) { Text("Playback volume") }
                .labelsHidden()
        }
        LabeledContent("Audio output", value: "System output")
        Picker("Keyboard layout", selection: $settings.keyboardGeometry) {
            ForEach(KeyboardGeometry.allCases, id: \.self) { geometry in
                Text(geometry.rawValue).tag(geometry)
            }
        }
    }
}
