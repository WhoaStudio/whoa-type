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

/// What the periodic health check should do. Pure so the recovery rules can be unit tested.
nonisolated enum HealthAction: Equatable {
    case none, rebuild, reconcile, retryCapture, giveUp

    static let maxCaptureRetries = 3

    static func decide(soundEnabled: Bool, engineRunning: Bool, wasAuthorized: Bool, authorized: Bool,
                       captureActive: Bool, hasError: Bool, retries: Int) -> HealthAction {
        guard soundEnabled else { return .none }
        if !engineRunning { return .rebuild }
        if wasAuthorized != authorized { return .reconcile }
        if authorized && !captureActive && !hasError {
            return retries < maxCaptureRetries ? .retryCapture : .giveUp
        }
        return .none
    }
}
