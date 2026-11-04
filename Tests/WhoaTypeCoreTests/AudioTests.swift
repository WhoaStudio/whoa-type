import Foundation
import Testing
@testable import WhoaTypeCore

struct AudioTests {
    static var resourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("whoa-type/Resources/SoundPacks")
    }
    static var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Audio")
    }
    static func manifest() throws -> SoundPackManifest {
        try JSONDecoder().decode(SoundPackManifest.self, from: Data(contentsOf: fixtureRoot.appendingPathComponent("manifest.json")))
    }
    @Test func ringCapacityAndRepeatedWraparound() {
        let ring = SPSCRing<Int>(capacity: 256, empty: -1)
        for iteration in 0..<100 {
            for i in 0..<256 { #expect(ring.push(iteration * 256 + i)) }
            #expect(!ring.push(-2))
            for i in 0..<256 { #expect(ring.pop() == iteration * 256 + i) }
            #expect(ring.pop() == nil)
        }
    }
    @Test func concurrentRingPreservesOrder() async {
        let ring = SPSCRing<Int>(capacity: 256, empty: -1)
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for i in 0..<100_000 { while !ring.push(i) {} }
                return true
            }
            group.addTask {
                for i in 0..<100_000 {
                    var value: Int?
                    while value == nil { value = ring.pop() }
                    if value != i { return false }
                }
                return true
            }
            for await valid in group { #expect(valid) }
        }
    }
    @Test func bundledPacksValidateAndConvert() async throws {
        let repository = SoundPackRepository()
        let packs = try await repository.discover(in: Self.resourceRoot)
        let expectedFolders: Set<String> = ["alpacas", "blackink", "bluealps", "boxnavy", "buckling", "mxblack", "mxblue", "mxbrown", "nkcream2", "nkcream3", "osu", "redink", "topre", "turquoise", "typewriter"]
        #expect(Set(packs.map { $0.root.lastPathComponent }) == expectedFolders)
        #expect(Set(packs.map(\.name)).count == packs.count)
        for pack in packs {
            let bank = try await repository.load(pack, rate: 48000)
            #expect(bank.header.pointee.ranges[0].count > 0)
            #expect(bank.header.pointee.ranges[1].count > 0)
            #expect(bank.header.pointee.samples[0].count <= 24032)
        }
    }
    @Test func rendererPitchPairPanGainAndSwap() throws {
        let m = try Self.manifest()
        let bank = PreparedSoundBank(pcm: [Array(repeating: 0.5, count: 24000)],
            variants: [0,0], ranges: Array(repeating: SampleRange(start: 0, count: 1), count: 256), manifest: m)
        let ring = TriggerRing(capacity: 256, empty: AudioTrigger())
        let mailbox = AudioControlMailbox()
        let renderer = AudioRenderer(triggers: ring, mailbox: mailbox, rate: 48000)
        var left = [Float](repeating: 0, count: 256)
        var right = left
        func render() {
            left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in
                AudioRenderer.render(state: renderer.state, triggers: ring, mailbox: mailbox, frames: 256, left: l.baseAddress!, right: r.baseAddress!)
            }}
        }
        #expect(mailbox.commands.push(AudioControl(kind: .bankTransition, bank: bank.header, sequence: 1)))
        render()
        #expect(mailbox.acknowledged.load(ordering: .acquiring) == 1)
        #expect(ring.push(AudioTrigger(slot: 0, phase: .down, pan: -1)))
        render()
        #expect(left.contains { $0 > 0 })
        #expect(right.allSatisfy { abs($0) < 0.000001 })
        let pitch = renderer.state.pointee.pitches[0]
        #expect((pow(2, -215.0 / 1200)...pow(2, -145.0 / 1200)).contains(pitch))
        #expect(ring.push(AudioTrigger(slot: 0, phase: .up, pan: -1)))
        render()
        #expect(renderer.state.pointee.pitches[0] == 0)
        #expect(renderer.state.pointee.voices[1].increment == pitch)
        #expect(mailbox.commands.push(AudioControl(gain: 0)))
        render(); render()
        #expect(left.allSatisfy { $0 == 0 })
        #expect(mailbox.commands.push(AudioControl(kind: .discontinuity, sequence: 2)))
        render()
        #expect(mailbox.acknowledged.load(ordering: .acquiring) == 2)
        #expect((0..<64).allSatisfy { !renderer.state.pointee.voices[$0].active })
        #expect(ring.pop() == nil)
        withExtendedLifetime(bank) {}
    }
    @Test func makeupGainDoublesLinearOutputAndPreservesMute() throws {
        let manifest = try JSONDecoder().decode(SoundPackManifest.self,
            from: Data(contentsOf: Self.resourceRoot.appendingPathComponent("alpacas/manifest.json")))
        let bank = PreparedSoundBank(pcm: [Array(repeating: 0.1, count: 24000)], variants: [0],
            ranges: Array(repeating: SampleRange(start: 0, count: 1), count: 256), manifest: manifest)
        let renderer = AudioRenderer(triggers: TriggerRing(capacity: 256, empty: AudioTrigger()),
            mailbox: AudioControlMailbox(), rate: 48000)
        renderer.state.pointee.bank = bank.header
        renderer.state.pointee.gain = 0.5
        AudioRenderer.trigger(AudioTrigger(slot: 127, phase: .down, pan: 0), state: renderer.state)
        var left = [Float](repeating: 0, count: 512)
        var right = left
        func render() {
            left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in
                AudioRenderer.render(state: renderer.state, triggers: renderer.triggers, mailbox: renderer.mailbox,
                    frames: 512, left: l.baseAddress!, right: r.baseAddress!)
            }}
        }
        render()
        let expected = 0.1 * bank.header.pointee.gain * cos(Float.pi / 4)
        #expect(abs(left[511] - expected) < 0.000001)
        #expect(abs(right[511] - expected) < 0.000001)
        #expect(renderer.mailbox.commands.push(AudioControl(gain: 0)))
        render()
        #expect(left[511] == 0 && right[511] == 0)
        withExtendedLifetime(bank) {}
    }
    @Test func fullVoiceLoadIsFiniteAndBounded() throws {
        let m = try JSONDecoder().decode(SoundPackManifest.self,
            from: Data(contentsOf: Self.resourceRoot.appendingPathComponent("alpacas/manifest.json")))
        let bank = PreparedSoundBank(pcm: [Array(repeating: 100, count: 24000)], variants: [0], ranges: Array(repeating: SampleRange(start: 0, count: 1), count: 256), manifest: m)
        let ring = TriggerRing(capacity: 256, empty: AudioTrigger())
        let mailbox = AudioControlMailbox()
        let renderer = AudioRenderer(triggers: ring, mailbox: mailbox, rate: 48000)
        renderer.state.pointee.bank = bank.header
        var l = [Float](repeating: 0, count: 128); var r = l
        for batch in 0..<20 {
            for i in 0..<256 { _ = ring.push(AudioTrigger(slot: UInt16(i % 128), phase: .down, pan: Float(batch % 3 - 1))) }
            l.withUnsafeMutableBufferPointer { left in r.withUnsafeMutableBufferPointer { right in
                AudioRenderer.render(state: renderer.state, triggers: ring, mailbox: mailbox, frames: 128, left: left.baseAddress!, right: right.baseAddress!)
            }}
            #expect(l.allSatisfy { $0.isFinite && abs($0) <= 1 })
            #expect(r.allSatisfy { $0.isFinite && abs($0) <= 1 })
        }
        withExtendedLifetime(bank) {}
    }
    @Test func physicalGeometryAndModifierPairs() {
        for geometry in KeyboardGeometry.allCases {
            let pans = KeyMapper.makePans(geometry)
            #expect(pans.count == 128)
            #expect(pans.allSatisfy { $0.isFinite && abs($0) <= 0.7 })
            #expect(pans[0] < pans[37])
            #expect(pans[127] == 0)
        }
        for (left, right, lbit, rbit) in [(56,60,2,4),(59,62,1,0x2000),(58,61,0x20,0x40),(55,54,8,16)] {
            #expect(KeyMapper.modifierDown(code: UInt16(left), flags: UInt64(lbit | rbit)) == true)
            #expect(KeyMapper.modifierDown(code: UInt16(right), flags: UInt64(lbit | rbit)) == true)
            #expect(KeyMapper.modifierDown(code: UInt16(left), flags: UInt64(rbit)) == false)
            #expect(KeyMapper.modifierDown(code: UInt16(right), flags: UInt64(rbit)) == true)
        }
        #expect(KeyMapper.modifierDown(code: 57, flags: 0x10000) == true)
        #expect(KeyMapper.modifierDown(code: 57, flags: 0) == false)
        #expect(KeyMapper.modifierDown(code: 63, flags: .max) == nil)
    }
}

struct KeyCharacterTests {
    @Test func largeKeysAreHeavierAndModifiersLighter() {
        let normal = KeyMapper.soundCharacter(127)
        for code: UInt16 in [49, 36, 76, 51, 117] {
            let profile = KeyMapper.soundCharacter(code)
            #expect(profile.gain > normal.gain)
            #expect(profile.pitchBias < normal.pitchBias)
        }
        for code: UInt16 in [54,55,56,58,59,60,61,62] {
            let profile = KeyMapper.soundCharacter(code)
            #expect(profile.gain < normal.gain)
            #expect(profile.pitchBias > normal.pitchBias)
        }
        #expect(KeyMapper.soundCharacter(0).gain != KeyMapper.soundCharacter(1).gain)
        #expect(normal.gain == 1)
        #expect(normal.pitchBias == 0)
    }
    @Test func renderingShadesSameSampleAndKeepsPairedPitchWithinPackBounds() throws {
        let manifest = try AudioTests.manifest()
        let bank = PreparedSoundBank(pcm: [Array(repeating: 0.5, count: 24000)], variants: [0],
            ranges: Array(repeating: SampleRange(start: 0, count: 1), count: 256), manifest: manifest)
        func voice(for slot: UInt16, seed: UInt64) -> Voice {
            let renderer = AudioRenderer(triggers: TriggerRing(capacity: 256, empty: AudioTrigger()),
                mailbox: AudioControlMailbox(), rate: 48000, seed: seed)
            renderer.state.pointee.bank = bank.header
            AudioRenderer.trigger(AudioTrigger(slot: slot, phase: .down), state: renderer.state)
            let down = renderer.state.pointee.voices[0]
            AudioRenderer.trigger(AudioTrigger(slot: slot, phase: .up), state: renderer.state)
            #expect(renderer.state.pointee.voices[1].increment == down.increment)
            let cents = 1200 * log2(down.increment)
            #expect(cents >= Double(manifest.pitchCents.min) - 0.001)
            #expect(cents <= Double(manifest.pitchCents.max) + 0.001)
            #expect(down.sample.data == bank.header.pointee.samples[0].data)
            return down
        }
        for seed in UInt64(1)...100 {
            let space = voice(for: 49, seed: seed)
            let modifier = voice(for: 55, seed: seed)
            #expect(space.left > modifier.left)
            #expect(space.increment < modifier.increment)
        }
        withExtendedLifetime(bank) {}
    }
}

struct PositionalToneTests {
    @Test func sameRecordingHasAudiblePitchAndToneSpreadAcrossKeyboard() throws {
        let manifest = try AudioTests.manifest()
        let pcm = (0..<24000).map { Float(sin(2 * Double.pi * 6000 * Double($0) / 48000)) * 0.2 }
        let bank = PreparedSoundBank(pcm: [pcm], variants: [0],
            ranges: Array(repeating: SampleRange(start: 0, count: 1), count: 256), manifest: manifest)
        func output(pan: Float) -> (pitch: Double, energy: Double, coefficient: Float) {
            let renderer = AudioRenderer(triggers: TriggerRing(capacity: 256, empty: AudioTrigger()),
                mailbox: AudioControlMailbox(), rate: 48000, seed: 123)
            renderer.state.pointee.bank = bank.header
            AudioRenderer.trigger(AudioTrigger(slot: 0, phase: .down, pan: pan), state: renderer.state)
            let voice = renderer.state.pointee.voices[0]
            var l = [Float](repeating: 0, count: 2048); var r = l
            l.withUnsafeMutableBufferPointer { left in r.withUnsafeMutableBufferPointer { right in
                AudioRenderer.render(state: renderer.state, triggers: renderer.triggers, mailbox: renderer.mailbox,
                    frames: 2048, left: left.baseAddress!, right: right.baseAddress!)
            }}
            var energy: Double = 0
            for i in 256..<2048 {
                let left = Double(l[i]); let right = Double(r[i])
                energy += left * left + right * right
            }
            AudioRenderer.trigger(AudioTrigger(slot: 0, phase: .up, pan: pan), state: renderer.state)
            #expect(renderer.state.pointee.voices[1].increment == voice.increment)
            #expect(voice.sample.data == bank.header.pointee.samples[0].data)
            return (voice.increment, energy, voice.toneCoefficient)
        }
        let left = output(pan: -0.7)
        let center = output(pan: 0)
        let right = output(pan: 0.7)
        #expect(left.pitch < center.pitch && center.pitch < right.pitch)
        #expect(abs(1200 * log2(right.pitch / left.pitch) - 360) < 0.01)
        #expect(left.coefficient < center.coefficient && center.coefficient < right.coefficient)
        #expect(right.energy > left.energy * 1.5)
        withExtendedLifetime(bank) {}
    }
    @Test func selectedGeometryChangesTimbreAndUnknownKeysStayCentered() {
        let ansi = KeyMapper.makePans(.ansi)
        let iso = KeyMapper.makePans(.iso)
        #expect(KeyMapper.positionCharacter(pan: ansi[0]).pitchCents < KeyMapper.positionCharacter(pan: ansi[37]).pitchCents)
        #expect(KeyMapper.positionCharacter(pan: ansi[10]).pitchCents != KeyMapper.positionCharacter(pan: iso[10]).pitchCents)
        #expect(KeyMapper.positionCharacter(pan: ansi[127]).pitchCents == 0)
    }
}
