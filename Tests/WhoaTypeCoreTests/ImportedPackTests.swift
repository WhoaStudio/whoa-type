import Foundation
import Testing
@testable import WhoaTypeCore

struct ImportedPackTests {
    @Test(arguments: ["alpacas", "blackink"])
    func physicalKeysSelectDedicatedRecordings(_ name: String) async throws {
        let root = AudioTests.resourceRoot.appendingPathComponent(name)
        let manifest = try JSONDecoder().decode(SoundPackManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let bank = try await SoundPackRepository().load(SoundPack(root: root, manifest: manifest), rate: 48000)
        let header = bank.header.pointee
        // Physical macOS A, Space and Return select three distinct sample sets.
        let indices = [0, 49, 36].map { code in
            header.variants[header.ranges[code * 2].start]
        }
        #expect(Set(indices).count == 3)
        #expect(manifest.keys["49"] == "space")
        #expect(manifest.keys["36"] == "enter")
        for code in [0, 49, 36] {
            let down = header.variants[header.ranges[code * 2].start]
            let up = header.variants[header.ranges[code * 2 + 1].start]
            #expect(down != up)
        }
    }
    @Test func pressOnlyPackHasSilentRelease() async throws {
        let root = AudioTests.resourceRoot.appendingPathComponent("osu")
        let manifest = try JSONDecoder().decode(SoundPackManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let bank = try await SoundPackRepository().load(SoundPack(root: root, manifest: manifest), rate: 48000)
        let header = bank.header.pointee
        let index = header.variants[header.ranges[1].start]
        let sample = header.samples[index]
        let data = try #require(sample.data)
        #expect((0..<sample.count).allSatisfy { data[$0] == 0 })
    }
}
