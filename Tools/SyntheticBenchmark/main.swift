import Foundation
import Dispatch
import Darwin

// Offline synthetic workload only. Never connects to an event tap or stores input.
let manifest = SoundPackManifest(schemaVersion: 1, id: "synthetic", displayName: "Synthetic", license: nil,
    gainDB: -12, pitchCents: .init(min: -35, max: 35), samples: [:], fallbackGroup: "", keyGroups: [:], keys: [:], preview: [])
let pcm = (0..<24000).map { Float(sin(Double($0) * 0.1)) * 0.25 }
let bank = PreparedSoundBank(pcm: [pcm], variants: [0], ranges: Array(repeating: SampleRange(start: 0, count: 1), count: 256), manifest: manifest)
let triggers = TriggerRing(capacity: 256, empty: AudioTrigger())
let mailbox = AudioControlMailbox()
let renderer = AudioRenderer(triggers: triggers, mailbox: mailbox, rate: 48000)
renderer.state.pointee.bank = bank.header
let left = UnsafeMutablePointer<Float>.allocate(capacity: 128)
let right = UnsafeMutablePointer<Float>.allocate(capacity: 128)
left.initialize(repeating: 0, count: 128); right.initialize(repeating: 0, count: 128)
let begin = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "whoa_probe_begin").map { unsafeBitCast($0, to: (@convention(c) () -> Void).self) }
let end = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "whoa_probe_end").map { unsafeBitCast($0, to: (@convention(c) () -> UInt64).self) }
var allocationActivity: UInt64 = 0
var durations = [UInt64](); durations.reserveCapacity(3000)
for batch in 0..<3500 {
    for key in 0..<64 { _ = triggers.push(AudioTrigger(slot: UInt16(key), phase: batch % 2 == 0 ? .down : .up, pan: Float(key) / 63 * 1.4 - 0.7)) }
    let start = DispatchTime.now().uptimeNanoseconds
    if batch >= 500 { begin?() }
    AudioRenderer.render(state: renderer.state, triggers: triggers, mailbox: mailbox, frames: 128, left: left, right: right)
    if batch >= 500 { allocationActivity += end?() ?? 0 }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    if batch >= 500 { durations.append(elapsed) }
}
durations.sort()
func percentile(_ p: Double) -> Double { Double(durations[min(durations.count - 1, Int(Double(durations.count - 1) * p))]) / 1_000_000 }
print("Offline synthetic benchmark; 64 overlapping voices, 64 triggers/quantum, 128 frames, 48000 Hz, 3000 measured quanta")
print(String(format: "Render time (ms): p50 %.4f; p95 %.4f; p99 %.4f; max %.4f", percentile(0.5), percentile(0.95), percentile(0.99), percentile(1)))
if begin != nil { print("Allocator activity during 3000 warmed render callbacks: \(allocationActivity)") }
print("This excludes OS input delivery, output hardware, transport latency, and underruns. No physical latency claim.")
left.deinitialize(count: 128); left.deallocate(); right.deinitialize(count: 128); right.deallocate()
withExtendedLifetime(bank) {}
