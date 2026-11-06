import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updater: UpdateController

    var body: some View {
        SettingsGroup("Updates") {
            LabeledContent("Current version", value: updater.currentVersion)
            LabeledContent("Last checked") {
                if let date = updater.lastChecked {
                    Text(date, format: .dateTime.month().day().hour().minute())
                } else {
                    Text("Never")
                }
            }
            Toggle("Automatically check for updates", isOn: $updater.automaticallyChecks)
                .toggleStyle(.switch)
                .disabled(!updater.isConfigured)
            Toggle("Automatically download and install updates", isOn: $updater.automaticallyDownloads)
                .toggleStyle(.switch)
                .disabled(!updater.isConfigured || !updater.automaticallyChecks)
            Picker("Check frequency", selection: $updater.checkInterval) {
                Text("Daily").tag(TimeInterval(86_400))
                Text("Weekly").tag(TimeInterval(604_800))
                Text("Monthly").tag(TimeInterval(2_592_000))
            }
            .disabled(!updater.isConfigured || !updater.automaticallyChecks)
            Text("Checks on launch and at the selected interval. Automatic updates install when you quit; you can also choose Install and Relaunch.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(updater.status)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Update status: \(updater.status)")
            CheckForUpdatesButton(updater: updater)
        }
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater: UpdateController

    var body: some View {
        Button(updater.availableVersion.map { "Version \($0) Available…" } ?? "Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.isConfigured || !updater.canCheckForUpdates)
    }
}
