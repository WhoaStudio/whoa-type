import Foundation

nonisolated enum KeyboardGeometry: String, CaseIterable, Sendable {
    case ansi = "ANSI", iso = "ISO", jis = "JIS"
}
