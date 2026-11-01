import SwiftUI

struct PermissionOnboardingView: View {
    var permission: PermissionController
    var retry: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(permission.authorized ? "Input Monitoring granted" : "Input Monitoring required")
                .font(.headline)
            Text("Only physical key position and key/button press/release phase are used transiently to play sounds. Typed text and cursor position are never read or stored.")
            Text("Input Monitoring lets Whoa Type play sounds for keyboard and mouse input across apps. No microphone, screen recording, or Accessibility access is needed.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !permission.authorized {
                Text("Enable Whoa Type in System Settings → Privacy & Security → Input Monitoring. If it is not listed, request access first. Relaunch the app if macOS asks.")
                if permission.requestedThisSession {
                    Text("Access is still pending. Switch previews remain available.")
                        .foregroundStyle(.secondary)
                }
                Button("Request Input Monitoring") { permission.request(); retry() }
            }
            HStack {
                Button(permission.authorized ? "Manage Permission…" : "Open System Settings…") {
                    permission.openSystemSettings()
                }
                Button("Check Again") { permission.refresh(); retry() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission.refresh()
        }
    }
}
