import CoreGraphics
import Foundation
import Testing
@testable import WhoaTypeCore

struct PointerTests {
    @Test func buttonsHaveIndependentPairedStateAndCenteredSound() throws {
        var held: UInt32 = 0
        let left = try #require(PointerMapper.trigger(type: .leftMouseDown, button: 0, held: &held))
        let right = try #require(PointerMapper.trigger(type: .rightMouseDown, button: 1, held: &held))
        let last = try #require(PointerMapper.trigger(type: .otherMouseDown, button: 31, held: &held))
        #expect(left.slot == 128 && right.slot == 129 && last.slot == 159)
        #expect(left.pan == 0 && right.pan == 0 && last.pan == 0)
        #expect(left.phase == .down)
        #expect(PointerMapper.trigger(type: .leftMouseDown, button: 0, held: &held) == nil)
        #expect(PointerMapper.trigger(type: .leftMouseDragged, button: 0, held: &held) == nil)
        let release = try #require(PointerMapper.trigger(type: .leftMouseUp, button: 0, held: &held))
        #expect(release.slot == left.slot && release.phase == .up)
        #expect(held & 2 != 0 && held & (UInt32(1) << 31) != 0)
        #expect(PointerMapper.trigger(type: .leftMouseUp, button: 0, held: &held) == nil)
        // Second click in a double-click is a fresh pair, not a repeat.
        #expect(PointerMapper.trigger(type: .leftMouseDown, button: 0, held: &held) != nil)
        #expect(PointerMapper.trigger(type: .leftMouseUp, button: 0, held: &held) != nil)
        held = 0 // capture stop/restart clears transient button holds
        #expect(PointerMapper.trigger(type: .rightMouseUp, button: 1, held: &held) == nil)
        #expect(PointerMapper.trigger(type: .otherMouseDown, button: -1, held: &held) == nil)
        #expect(PointerMapper.trigger(type: .otherMouseDown, button: 32, held: &held) == nil)
        #expect(PointerMapper.trigger(type: .scrollWheel, button: 0, held: &held) == nil)
        #expect(held == 0)
    }
    @Test func tapMaskIncludesOnlyButtonTransitions() {
        for type: CGEventType in [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp] {
            #expect(PointerMapper.eventMask & (CGEventMask(1) << type.rawValue) != 0)
        }
        for type: CGEventType in [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel] {
            #expect(PointerMapper.eventMask & (CGEventMask(1) << type.rawValue) == 0)
        }
    }
    @Test func bundledMouseRecordingsReachRendererAndResetSafely() async throws {
        let manifest = try AudioTests.manifest()
        let pack = SoundPack(root: AudioTests.fixtureRoot, manifest: manifest)
        let bank = try await SoundPackRepository().load(pack, rate: 48000)
        #expect(bank.header.pointee.slotCount == SoundSlot.count)
        let header = bank.header.pointee
        let down = header.variants[header.ranges[256].start]
        let up = header.variants[header.ranges[257].start]
        #expect(down != up)
        #expect(down != header.variants[header.ranges[0].start])
        let ring = TriggerRing(capacity: 256, empty: AudioTrigger())
        let mailbox = AudioControlMailbox()
        let renderer = AudioRenderer(triggers: ring, mailbox: mailbox, rate: 48000)
        renderer.state.pointee.bank = bank.header
        AudioRenderer.trigger(AudioTrigger(slot: 159, phase: .down), state: renderer.state)
        let pitch = renderer.state.pointee.pitches[159]
        let pressRange = header.ranges[256]
        #expect((0..<pressRange.count).contains { offset in
            renderer.state.pointee.voices[0].sample.data == header.samples[header.variants[pressRange.start + offset]].data
        })
        #expect(renderer.state.pointee.voices[0].toneMix == 0)
        #expect(abs(renderer.state.pointee.voices[0].left - renderer.state.pointee.voices[0].right) < 0.000001)
        var l = [Float](repeating: 0, count: 1024); var r = l
        func render() {
            l.withUnsafeMutableBufferPointer { left in r.withUnsafeMutableBufferPointer { right in
                AudioRenderer.render(state: renderer.state, triggers: ring, mailbox: mailbox, frames: 1024,
                    left: left.baseAddress!, right: right.baseAddress!)
            }}
        }
        render()
        #expect(l.contains { abs($0) > 0.00001 })
        AudioRenderer.trigger(AudioTrigger(slot: 159, phase: .up), state: renderer.state)
        #expect(renderer.state.pointee.voices[1].sample.data == header.samples[up].data)
        #expect(renderer.state.pointee.voices[1].increment == pitch)
        #expect(renderer.state.pointee.pitches[159] == 0)
        #expect(mailbox.commands.push(AudioControl(kind: 2, sequence: 1)))
        render()
        #expect(mailbox.acknowledged.load(ordering: .acquiring) == 1)
        #expect((0..<SoundSlot.count).allSatisfy { renderer.state.pointee.pitches[$0] == 0 })
        withExtendedLifetime(bank) {}
    }
    @Test func keyboardOnlyPackDoesNotSubstituteKeyboardSoundForClick() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: AudioTests.fixtureRoot.appendingPathComponent("sample.wav"), to: root.appendingPathComponent("sample.wav"))
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: AudioTests.fixtureRoot.appendingPathComponent("manifest.json"))) as? [String: Any])
        json["samples"] = ["standard": ["down": ["sample.wav"], "up": ["sample.wav"]]]
        let manifest = try JSONDecoder().decode(SoundPackManifest.self, from: JSONSerialization.data(withJSONObject: json))
        let bank = try await SoundPackRepository().load(SoundPack(root: root, manifest: manifest), rate: 48000)
        #expect(bank.header.pointee.ranges[256].count == 0)
        let renderer = AudioRenderer(triggers: TriggerRing(capacity: 256, empty: AudioTrigger()), mailbox: AudioControlMailbox(), rate: 48000)
        renderer.state.pointee.bank = bank.header
        AudioRenderer.trigger(AudioTrigger(slot: 128), state: renderer.state)
        #expect(!renderer.state.pointee.voices[0].active)
        withExtendedLifetime(bank) {}
    }
}

struct ClickVariationTests {
    @Test func clicksUseEveryRecordingWithoutImmediateRepeats() async throws {
        let pack = SoundPack(root: AudioTests.fixtureRoot, manifest: try AudioTests.manifest())
        let bank = try await SoundPackRepository().load(pack, rate: 48000)
        let variantCount = try #require(pack.manifest.samples["pointer"]?.down.count)
        #expect(variantCount > 1)
        #expect(bank.header.pointee.ranges[256].count == variantCount)
        let mailbox = AudioControlMailbox()
        let renderer = AudioRenderer(triggers: TriggerRing(capacity: 256, empty: AudioTrigger()), mailbox: mailbox, rate: 48000)
        renderer.state.pointee.bank = bank.header
        var previous: UnsafeMutablePointer<Float>?
        var heard = Set<Int>()
        for i in 0..<300 {
            let slot = UInt16(128 + i % 3)
            AudioRenderer.trigger(AudioTrigger(slot: slot, phase: .down), state: renderer.state)
            var newest = renderer.state.pointee.voices[0]
            for j in 1..<64 {
                let voice = renderer.state.pointee.voices[j]
                if voice.age > newest.age { newest = voice }
            }
            let sample = try #require(newest.sample.data)
            #expect(sample != previous)
            previous = sample
            heard.insert(Int(bitPattern: sample))
            AudioRenderer.trigger(AudioTrigger(slot: slot, phase: .up), state: renderer.state)
        }
        #expect(heard.count == variantCount)
        #expect(mailbox.commands.push(AudioControl(kind: 2, sequence: 1)))
        var l = [Float](repeating: 0, count: 256); var r = l
        l.withUnsafeMutableBufferPointer { left in r.withUnsafeMutableBufferPointer { right in
            AudioRenderer.render(state: renderer.state, triggers: renderer.triggers, mailbox: mailbox, frames: 256,
                left: left.baseAddress!, right: right.baseAddress!)
        }}
        #expect(renderer.state.pointee.lastPointerDownVariant == -1)
        withExtendedLifetime(bank) {}
    }
    @Test func oneVariantPointerPackRemainsPlayable() throws {
        let bank = PreparedSoundBank(pcm: [[0.1,0.2,0.1]], variants: [0],
            ranges: Array(repeating: SampleRange(start: 0, count: 1), count: SoundSlot.count * 2),
            manifest: try AudioTests.manifest())
        let renderer = AudioRenderer(triggers: TriggerRing(capacity: 256, empty: AudioTrigger()), mailbox: AudioControlMailbox(), rate: 48000)
        renderer.state.pointee.bank = bank.header
        for _ in 0..<20 {
            AudioRenderer.trigger(AudioTrigger(slot: 128, phase: .down), state: renderer.state)
            #expect(renderer.state.pointee.lastPointerDownVariant == 0)
            AudioRenderer.trigger(AudioTrigger(slot: 128, phase: .up), state: renderer.state)
        }
        withExtendedLifetime(bank) {}
    }
}
