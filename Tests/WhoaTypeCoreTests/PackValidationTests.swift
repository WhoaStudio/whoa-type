import Foundation
import Testing
@testable import WhoaTypeCore

struct PackValidationTests {
    private func altered(_ mutate: (inout [String: Any]) -> Void) throws -> SoundPackManifest {
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: AudioTests.fixtureRoot.appendingPathComponent("manifest.json"))) as? [String: Any])
        mutate(&json)
        return try JSONDecoder().decode(SoundPackManifest.self, from: JSONSerialization.data(withJSONObject: json))
    }
    @Test(arguments: ["schema", "gain", "pitch", "missing", "code", "preview", "release", "escape"])
    func malformedPacksAreRejected(_ kind: String) throws {
        let m = try altered { json in
            switch kind {
            case "schema": json["schemaVersion"] = 2
            case "gain": json["gainDB"] = 10
            case "pitch": json["pitchCents"] = ["min": -101, "max": 0]
            case "missing": json["fallbackGroup"] = "missing"
            case "code": json["keys"] = ["128": "standard"]
            case "preview": json["preview"] = [["atMs": 2001, "keyCode": 0, "phase": "down"]]
            case "release": json["samples"] = ["standard": ["down": ["sample.wav"], "up": []]]
            case "escape": json["samples"] = ["standard": ["down": ["../sample.wav"], "up": ["sample.wav"]]]
            default: break
            }
        }
        #expect(throws: (any Error).self) {
            try SoundPackValidator.validate(m, root: AudioTests.fixtureRoot, rate: 48000)
        }
    }
    @Test func externalSymlinkIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("sample.wav"), withDestinationURL: AudioTests.fixtureRoot.appendingPathComponent("sample.wav"))
        #expect(throws: (any Error).self) { try SoundPackValidator.file("sample.wav", in: root) }
        #expect(throws: (any Error).self) { try SoundPackValidator.file("/etc/passwd", in: root) }
    }
    @Test func lookupOrderIsPerKeyThenGroupThenFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["sample.wav", "group.wav", "key.wav"] {
            try FileManager.default.copyItem(at: AudioTests.fixtureRoot.appendingPathComponent("sample.wav"), to: root.appendingPathComponent(name))
        }
        let manifest = try altered { json in
            json["samples"] = [
                "standard": ["down": ["sample.wav"], "up": ["sample.wav"]],
                "group": ["down": ["group.wav"], "up": ["group.wav"]],
                "key": ["down": ["key.wav"], "up": ["key.wav"]]]
            json["keyGroups"] = ["0": "group", "1": "group"]
            json["keys"] = ["0": "key"]
        }
        let bank = try await SoundPackRepository().load(SoundPack(root: root, manifest: manifest), rate: 44100)
        let header = bank.header.pointee
        #expect(header.variants[header.ranges[0].start] == 1) // key.wav
        #expect(header.variants[header.ranges[2].start] == 0) // group.wav
        #expect(header.variants[header.ranges[4].start] == 2) // sample.wav
    }
}

struct PackDiscoveryTests {
    @Test func duplicateIDsAreRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["one", "two"] {
            try FileManager.default.copyItem(at: AudioTests.fixtureRoot, to: root.appendingPathComponent(name))
        }
        do {
            _ = try await SoundPackRepository().discover(in: root)
            Issue.record("Duplicate IDs accepted")
        } catch PackError.invalid(let message) { #expect(message == "Duplicate pack ID") }
    }
    @Test func fileAndMemoryCapsRejectBeforeDecode() throws {
        let m = try AudioTests.manifest()
        // Maximum supported conversion rate magnifies a 500 ms fixture enough
        // to exercise the aggregate bound without allocating decoded banks.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = AudioTests.fixtureRoot.appendingPathComponent("sample.wav")
        var files: [String] = []
        for i in 0..<200 {
            let name = "\(i).wav"
            try FileManager.default.linkItem(at: original, to: root.appendingPathComponent(name))
            files.append(name)
        }
        let memoryManifest = SoundPackManifest(schemaVersion: 1, id: "limit", displayName: "Limit", license: nil,
            gainDB: m.gainDB, pitchCents: m.pitchCents,
            samples: ["standard": .init(down: files, up: files)], fallbackGroup: "standard", keyGroups: [:], keys: [:], preview: [])
        #expect(throws: (any Error).self) { try SoundPackValidator.validate(memoryManifest, root: root, rate: 192000) }
        let countManifest = SoundPackManifest(schemaVersion: 1, id: "limit", displayName: "Limit", license: nil,
            gainDB: m.gainDB, pitchCents: m.pitchCents,
            samples: ["standard": .init(down: (0..<513).map { "\($0).wav" }, up: ["0.wav"])],
            fallbackGroup: "standard", keyGroups: [:], keys: [:], preview: [])
        #expect(throws: (any Error).self) { try SoundPackValidator.validate(countManifest, root: root, rate: 48000) }
    }
    @Test func cheapDiscoverySkipsAudioButStillChecksPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // A file that is not decodable audio passes cheap discovery but fails full validation.
        try Data("not audio".utf8).write(to: root.appendingPathComponent("bad.wav"))
        let m = try AudioTests.manifest()
        let manifest = SoundPackManifest(schemaVersion: 1, id: "cheap", displayName: "Cheap", license: nil,
            gainDB: m.gainDB, pitchCents: m.pitchCents,
            samples: ["standard": .init(down: ["bad.wav"], up: ["bad.wav"])],
            fallbackGroup: "standard", keyGroups: [:], keys: [:], preview: [])
        #expect(throws: Never.self) { try SoundPackValidator.validate(manifest, root: root, rate: 48000, inspectAudio: false) }
        #expect(throws: (any Error).self) { try SoundPackValidator.validate(manifest, root: root, rate: 48000) }
        let missing = SoundPackManifest(schemaVersion: 1, id: "cheap", displayName: "Cheap", license: nil,
            gainDB: m.gainDB, pitchCents: m.pitchCents,
            samples: ["standard": .init(down: ["gone.wav"], up: ["gone.wav"])],
            fallbackGroup: "standard", keyGroups: [:], keys: [:], preview: [])
        #expect(throws: (any Error).self) { try SoundPackValidator.validate(missing, root: root, rate: 48000, inspectAudio: false) }
    }
}
