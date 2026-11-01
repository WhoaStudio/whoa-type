import Foundation
import ServiceManagement
import Observation

@MainActor @Observable
final class LoginItemService {
    private(set) var status = SMAppService.mainApp.status
    private(set) var errorMessage: String?
    var enabled: Bool { status == .enabled }
    var message: String {
        if let errorMessage { return errorMessage }
        switch status {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Approval required in System Settings → General → Login Items"
        case .notRegistered: return "Disabled"
        case .notFound: return "Login item unavailable"
        @unknown default: return "Unknown login-item status"
        }
    }
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        refresh()
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
