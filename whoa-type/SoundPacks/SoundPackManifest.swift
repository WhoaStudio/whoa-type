import Foundation

nonisolated enum KeyPhase: UInt8, Codable, Sendable { case down, up
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value { case "down": self = .down; case "up": self = .up
        default: throw PackError.invalid("Unknown phase") }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self == .down ? "down" : "up")
    }
}
nonisolated struct SoundPackManifest: Codable, Sendable {
    struct Pitch: Codable, Sendable { let min: Float; let max: Float }
    struct Samples: Codable, Sendable { let down: [String]; let up: [String] }
    struct PreviewEvent: Codable, Sendable { let atMs: Int; let keyCode: UInt16; let phase: KeyPhase }
    let schemaVersion: Int
    let id: String
    let displayName: String
    let license: String?
    let gainDB: Float
    let pitchCents: Pitch
    let samples: [String: Samples]
    let fallbackGroup: String
    let keyGroups: [String: String]
    let keys: [String: String]
    let preview: [PreviewEvent]
}
nonisolated enum PackError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}
nonisolated struct SoundPack: Identifiable, Sendable {
    let root: URL
    let manifest: SoundPackManifest
    var id: String { manifest.id }
    var name: String { manifest.displayName }
}
