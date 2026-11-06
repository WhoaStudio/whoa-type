import SwiftUI

struct PermissionOnboardingView: View {
    var permission: PermissionController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if permission.authorized {
                Label("Input Monitoring granted", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else {
                Text("Input Monitoring required")
                    .font(.headline)
            }
            Text("Only physical key position and key/button press/release phase are used transiently to play sounds. Typed text and cursor position are never read or stored.")
            Text("Input Monitoring lets Whoa Type play sounds for keyboard and mouse input across apps. No microphone, screen recording, or Accessibility access is needed.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !permission.authorized {
                Text("Enable Whoa Type in System Settings → Privacy & Security → Input Monitoring. Relaunch the app if macOS asks.")
                if permission.requestedThisSession {
                    Text("Access is still pending. Switch previews remain available.")
                        .foregroundStyle(.secondary)
                }
                Button("Open System Settings…") {
                    permission.request()
                    permission.openSystemSettings()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission.refresh()
        }
    }
}
