import Foundation

nonisolated enum AppState: Equatable {
    case soundOff, permissionRequired, preparingAudio, ready
    case captureUnavailable, audioUnavailable(String)

    var message: String {
        switch self {
        case .soundOff: "Sound off"
        case .permissionRequired: "Input Monitoring required"
        case .preparingAudio: "Preparing audio…"
        case .ready: "Ready"
        case .captureUnavailable: "Keyboard capture unavailable"
        case .audioUnavailable(let reason): "Audio unavailable: \(reason)"
        }
    }

    static func resolve(enabled: Bool, authorized: Bool, audioReady: Bool, captureActive: Bool) -> AppState {
        guard enabled else { return .soundOff }
        guard authorized else { return .permissionRequired }
        guard audioReady else { return .preparingAudio }
        return captureActive ? .ready : .captureUnavailable
    }
}
