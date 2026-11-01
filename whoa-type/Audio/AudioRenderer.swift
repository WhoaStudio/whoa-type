import Synchronization
import Foundation

nonisolated struct RenderState {
    var voices: UnsafeMutablePointer<Voice>
    var pitches: UnsafeMutablePointer<Double>
    var bank: UnsafeMutablePointer<BankHeader>?
    var pendingBank: UnsafeMutablePointer<BankHeader>?
    var sequence: UInt64 = 0
    var transition = 0
    var swap = false
    var gain: Float = 0
    var targetGain: Float = 0.5
    var random: UInt64
    var age: UInt64 = 0
    var fadeFrames: Int
    var sampleRate: Double
    var lastPointerDownVariant: Int = -1
}
nonisolated final class AudioRenderer: @unchecked Sendable {
    let state: UnsafeMutablePointer<RenderState>
    let triggers: TriggerRing
    let mailbox: AudioControlMailbox
    init(triggers: TriggerRing, mailbox: AudioControlMailbox, rate: Double, seed: UInt64 = 0x617564696f) {
        self.triggers = triggers; self.mailbox = mailbox
        let voices = UnsafeMutablePointer<Voice>.allocate(capacity: 64)
        voices.initialize(repeating: Voice(), count: 64)
        let pitches = UnsafeMutablePointer<Double>.allocate(capacity: SoundSlot.count)
        pitches.initialize(repeating: 0, count: SoundSlot.count)
        state = .allocate(capacity: 1)
        state.initialize(to: RenderState(voices: voices, pitches: pitches, random: seed == 0 ? 1 : seed, fadeFrames: max(1, Int(rate * 0.005)), sampleRate: rate))
    }
    @inline(__always) static func next(_ state: UnsafeMutablePointer<RenderState>) -> UInt64 {
        var x = state.pointee.random
        x ^= x << 13; x ^= x >> 7; x ^= x << 17
        state.pointee.random = x
        return x
    }
    @inline(__always) static func trigger(_ event: AudioTrigger, state s: UnsafeMutablePointer<RenderState>) {
        guard let bank = s.pointee.bank, Int(event.slot) < bank.pointee.slotCount, Int(event.slot) < SoundSlot.count else { return }
        let slot = Int(event.slot)
        let pointer = slot >= SoundSlot.keyboardCount
        let character = pointer ? KeySoundCharacter() : KeyMapper.soundCharacter(event.slot)
        let position = pointer ? PositionSoundCharacter(pitchCents: 0, cutoffHz: 10400, toneMix: 0) : KeyMapper.positionCharacter(pan: event.pan)
        let range = bank.pointee.ranges[slot * 2 + Int(event.phase.rawValue)]
        guard range.count > 0 else { return }
        let random = next(s)
        var variant = Int(random % UInt64(range.count))
        if pointer && event.phase == .down {
            let previous = s.pointee.lastPointerDownVariant
            if range.count > 1 && previous >= 0 && previous < range.count {
                variant = Int(random % UInt64(range.count - 1))
                if variant >= previous { variant += 1 }
            }
            s.pointee.lastPointerDownVariant = variant
        }
        let index = bank.pointee.variants[range.start + variant]
        var pitch = s.pointee.pitches[slot]
        if event.phase == .down || pitch == 0 {
            let unit = Float(next(s) >> 40) / Float(1 << 24)
            let halfRange = (bank.pointee.maxCents - bank.pointee.minCents) * 0.5
            let midpoint = bank.pointee.minCents + halfRange
            let center = midpoint + character.pitchBias * halfRange
            let variation = halfRange * (1 - abs(character.pitchBias)) * 0.35
            let cents = center + (unit * 2 - 1) * variation + position.pitchCents
            pitch = pow(2, Double(cents) / 1200)
            s.pointee.pitches[slot] = pitch
        }
        if event.phase == .up { s.pointee.pitches[slot] = 0 }
        let i = VoicePool.replacement(s.pointee.voices)
        let previous = s.pointee.voices[i]
        let angle = (max(-1, min(1, event.pan)) + 1) * .pi / 4
        s.pointee.age &+= 1
        s.pointee.voices[i] = Voice(sample: bank.pointee.samples[index], increment: pitch,
            left: cos(angle) * bank.pointee.gain * character.gain * event.gain, right: sin(angle) * bank.pointee.gain * character.gain * event.gain,
            toneCoefficient: Float(1 - exp(-2 * Double.pi * Double(position.cutoffHz) / s.pointee.sampleRate)),
            toneMix: position.toneMix, age: s.pointee.age, tailLeft: previous.lastLeft, tailRight: previous.lastRight,
            tailFrames: previous.active ? s.pointee.fadeFrames : 0, active: true)
    }
    // All pointees are preallocated. This method owns render memory exclusively.
    static func render(state s: UnsafeMutablePointer<RenderState>, triggers: TriggerRing,
                       mailbox: AudioControlMailbox, frames: Int,
                       left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        if s.pointee.transition == 0 {
            for _ in 0..<8 {
                guard let command = mailbox.commands.pop() else { break }
                if command.kind == 0 { s.pointee.targetGain = command.gain; continue }
                s.pointee.pendingBank = command.bank
                s.pointee.swap = command.kind == 1
                s.pointee.sequence = command.sequence
                s.pointee.transition = s.pointee.fadeFrames
                triggers.discard()
                break
            }
        }
        if s.pointee.transition == 0 {
            for _ in 0..<64 {
                guard let event = triggers.pop() else { break }
                trigger(event, state: s)
            }
        }
        for frame in 0..<frames {
            var l: Float = 0; var r: Float = 0
            for i in 0..<64 {
                let voice = s.pointee.voices.advanced(by: i)
                guard voice.pointee.active, let data = voice.pointee.sample.data else { continue }
                let index = Int(voice.pointee.cursor)
                if index >= voice.pointee.sample.count { voice.pointee = Voice(); continue }
                let nextIndex = min(index + 1, voice.pointee.sample.count - 1)
                let fraction = Float(voice.pointee.cursor - Double(index))
                let value = data[index] + (data[nextIndex] - data[index]) * fraction
                voice.pointee.toneState += voice.pointee.toneCoefficient * (value - voice.pointee.toneState)
                let shaped = value + voice.pointee.toneMix * (voice.pointee.toneState - value)
                var vl = shaped * voice.pointee.left
                var vr = shaped * voice.pointee.right
                if voice.pointee.tailFrames > 0 {
                    let mix = Float(voice.pointee.tailFrames) / Float(s.pointee.fadeFrames)
                    vl = vl * (1 - mix) + voice.pointee.tailLeft * mix
                    vr = vr * (1 - mix) + voice.pointee.tailRight * mix
                    voice.pointee.tailFrames -= 1
                }
                voice.pointee.lastLeft = vl; voice.pointee.lastRight = vr
                l += vl; r += vr
                voice.pointee.cursor += voice.pointee.increment
            }
            let difference = s.pointee.targetGain - s.pointee.gain
            let step = 1 / Float(s.pointee.fadeFrames)
            s.pointee.gain += max(-step, min(step, difference))
            // +6 dB makeup gain restores headroom lost to conservative pack levels.
            // Apply before peak protection; the saved user gain (including mute) stays authoritative.
            var gain = s.pointee.gain * 2
            if s.pointee.transition > 0 {
                gain *= Float(s.pointee.transition) / Float(s.pointee.fadeFrames)
                s.pointee.transition -= 1
                if s.pointee.transition == 0 {
                    for i in 0..<64 { s.pointee.voices[i] = Voice() }
                    for i in 0..<SoundSlot.count { s.pointee.pitches[i] = 0 }
                    s.pointee.lastPointerDownVariant = -1
                    if s.pointee.swap { s.pointee.bank = s.pointee.pendingBank }
                    s.pointee.pendingBank = nil
                    triggers.discard()
                    mailbox.acknowledged.store(s.pointee.sequence, ordering: .releasing)
                }
            }
            // Linear headroom below 0.9; continuous bounded soft knee above it.
            func clip(_ x: Float) -> Float {
                if x.isNaN { return 0 }
                if !x.isFinite { return x < 0 ? -1 : 1 }
                let a = abs(x)
                if a <= 0.9 { return x }
                let excess = a - 0.9
                let value = 0.9 + 0.1 * excess / (0.1 + excess)
                return x < 0 ? -value : value
            }
            left[frame] = clip(l * gain); right[frame] = clip(r * gain)
        }
    }
    deinit {
        state.pointee.voices.deinitialize(count: 64); state.pointee.voices.deallocate()
        state.pointee.pitches.deinitialize(count: SoundSlot.count); state.pointee.pitches.deallocate()
        state.deinitialize(count: 1); state.deallocate()
    }
}
