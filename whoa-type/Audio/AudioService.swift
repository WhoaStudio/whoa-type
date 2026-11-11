import Synchronization
import AVFoundation
import CoreAudio
import Foundation

nonisolated struct AudioRoute: Sendable {
    let status: String
    let isBluetooth: Bool
    let details: String?
}

// Only this queue owns graph lifecycle and retained banks. No mutable graph or
// owning bank references cross into the source callback.
nonisolated final class AudioService: @unchecked Sendable {
    let triggers = TriggerRing(capacity: 256, empty: AudioTrigger())
    let mailbox = AudioControlMailbox()
    private let queue = DispatchQueue(label: "WhoaType.audio-control", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var renderer: AudioRenderer?
    private var bank: PreparedSoundBank?
    private var sequence: UInt64 = 0
    private var gain: Float = 0.5
    private var gainRetryScheduled = false

    func prepare() async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if let engine = self.engine { continuation.resume(returning: engine.outputNode.outputFormat(forBus: 0).sampleRate); return }
                    let engine = AVAudioEngine()
                    let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
                    guard rate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
                        throw PackError.invalid("No audio output device")
                    }
                    let renderer = AudioRenderer(triggers: self.triggers, mailbox: self.mailbox, rate: rate, seed: UInt64.random(in: 1...UInt64.max))
                    let source = AVAudioSourceNode(format: format) { [renderer] _, _, count, buffers in
                        let list = UnsafeMutableAudioBufferListPointer(buffers)
                        guard list.count == 2, let l = list[0].mData, let r = list[1].mData else { return noErr }
                        AudioRenderer.render(state: renderer.state, triggers: renderer.triggers, mailbox: renderer.mailbox,
                            frames: Int(count), left: l.assumingMemoryBound(to: Float.self), right: r.assumingMemoryBound(to: Float.self))
                        return noErr
                    }
                    engine.attach(source)
                    engine.connect(source, to: engine.mainMixerNode, format: format)
                    engine.prepare()
                    try engine.start()
                    self.engine = engine; self.renderer = renderer
                    continuation.resume(returning: rate)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    // Caller serializes installs. Both banks remain retained until render ack.
    func install(_ next: PreparedSoundBank) async throws {
        try await command(kind: .bankTransition, next: next)
    }
    func reset() async throws { try await command(kind: .discontinuity, next: nil) }
    private func command(kind: AudioControl.Kind, next: PreparedSoundBank?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard let engine = self.engine, engine.isRunning else {
                    continuation.resume(throwing: PackError.invalid("Audio engine is not running")); return
                }
                self.sequence &+= 1
                let sequence = self.sequence
                let command = AudioControl(kind: kind, gain: self.gain, bank: next?.header, sequence: sequence)
                self.publish(command, attempts: 0) { result in
                    switch result {
                    case .failure(let error): continuation.resume(throwing: error)
                    case .success:
                        self.waitForAck(sequence, attempts: 0) { result in
                            // The closure retains next until ack. On failure, stopping
                            // the engine synchronizes callback completion before freeing.
                            if case .success = result, kind == .bankTransition { self.bank = next }
                            continuation.resume(with: result)
                        }
                    }
                }
            }
        }
    }
    private func publish(_ command: AudioControl, attempts: Int, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        if mailbox.commands.push(command) { completion(.success(())); return }
        guard attempts < 200 else { fail(completion); return }
        queue.asyncAfter(deadline: .now() + .milliseconds(5)) { self.publish(command, attempts: attempts + 1, completion: completion) }
    }
    private func waitForAck(_ sequence: UInt64, attempts: Int, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        if mailbox.acknowledged.load(ordering: .acquiring) >= sequence { completion(.success(())); return }
        guard attempts < 400 else { fail(completion); return }
        queue.asyncAfter(deadline: .now() + .milliseconds(5)) { self.waitForAck(sequence, attempts: attempts + 1, completion: completion) }
    }
    private func fail(_ completion: @Sendable (Result<Void, Error>) -> Void) {
        engine?.stop()
        engine = nil; renderer = nil; bank = nil
        mailbox.commands.discard(); triggers.discard()
        completion(.failure(PackError.invalid("Audio renderer did not acknowledge; retry audio")))
    }
    func setGain(_ value: Double) {
        queue.async {
            self.gain = Float(max(0, min(1, value)))
            // Gain is coalesced on the control queue if mailbox capacity is busy.
            self.sendGain()
        }
    }
    private func sendGain() {
        guard engine != nil else { return }
        if !mailbox.commands.push(AudioControl(gain: gain)), !gainRetryScheduled {
            gainRetryScheduled = true
            queue.asyncAfter(deadline: .now() + .milliseconds(10)) {
                self.gainRetryScheduled = false
                self.sendGain()
            }
        }
    }
    func isRunning() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.engine?.isRunning == true) }
        }
    }
    func outputRoute() async -> AudioRoute {
        await withCheckedContinuation { continuation in
            queue.async {
                var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var device = AudioDeviceID(0)
                var size = UInt32(MemoryLayout<AudioDeviceID>.size)
                guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else {
                    continuation.resume(returning: AudioRoute(
                        status: "System output unavailable", isBluetooth: false, details: nil))
                    return
                }
                var frames: UInt32 = 0
                address.mSelector = kAudioDevicePropertyBufferFrameSize
                _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &frames)
                var transport: UInt32 = 0
                address.mSelector = kAudioDevicePropertyTransportType
                _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
                let rate = self.engine?.outputNode.outputFormat(forBus: 0).sampleRate ?? 0
                let bluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
                let details = rate > 0 && frames > 0 ? "\(Int(rate)) Hz, \(frames) frames per buffer" : nil
                continuation.resume(returning: AudioRoute(
                    status: bluetooth ? "Bluetooth output" : "System output",
                    isBluetooth: bluetooth, details: details))
            }
        }
    }
    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.engine?.stop()
                self.engine = nil; self.renderer = nil; self.bank = nil
                self.mailbox.commands.discard(); self.triggers.discard()
                continuation.resume()
            }
        }
    }
}
