import AppKit
import CoreGraphics
import Observation

@MainActor @Observable
final class PermissionController {
    private(set) var authorized = CGPreflightListenEventAccess()
    private(set) var requestedThisSession = false
    func refresh() { authorized = CGPreflightListenEventAccess() }
    func request() {
        requestedThisSession = true
        _ = CGRequestListenEventAccess()
        refresh()
    }
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
}
