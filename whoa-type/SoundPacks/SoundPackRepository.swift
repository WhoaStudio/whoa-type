import Foundation
import Synchronization
import AVFoundation

nonisolated final class SoundPackRepository: Sendable {
    private let queue = DispatchQueue(label: "WhoaType.loader", qos: .userInitiated)
    func discover(in root: URL) async throws -> [SoundPack] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                    var packs: [SoundPack] = []
                    var ids = Set<String>()
                    for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                        let path = url.appendingPathComponent("manifest.json")
                        guard FileManager.default.fileExists(atPath: path.path) else { continue }
                        let data = try Data(contentsOf: path, options: .mappedIfSafe)
                        guard data.count <= 1_048_576 else { throw PackError.invalid("Manifest too large") }
                        let m = try JSONDecoder().decode(SoundPackManifest.self, from: data)
                        _ = try SoundPackValidator.validate(m, root: url, rate: 48000, inspectAudio: false)
                        guard ids.insert(m.id).inserted else { throw PackError.invalid("Duplicate pack ID") }
                        packs.append(SoundPack(root: url, manifest: m))
                    }
                    guard !packs.isEmpty else { throw PackError.invalid("No valid bundled packs") }
                    continuation.resume(returning: packs)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func load(_ pack: SoundPack, rate: Double, isCurrent: @escaping @Sendable () -> Bool = { true }) async throws -> PreparedSoundBank {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let files = try SoundPackValidator.validate(pack.manifest, root: pack.root, rate: rate)
                    let paths = files.keys.sorted()
                    var pcm: [PCMSample] = []
                    defer { for sample in pcm { sample.data?.deallocate() } }
                    for path in paths {
                        guard isCurrent() else { throw CancellationError() }
                        guard let fileURL = files[path] else { throw PackError.invalid("Missing sample \(path)") }
                        let file = try AVAudioFile(forReading: fileURL)
                        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                              let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
                              let converter = AVAudioConverter(from: file.processingFormat, to: format),
                              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(Double(file.length) * rate / file.processingFormat.sampleRate)) + 32)
                        else { throw PackError.invalid("PCM conversion unavailable") }
                        try file.read(into: input)
                        let source = ConversionInput(buffer: input)
                        var error: NSError?
                        let result = converter.convert(to: output, error: &error) { _, state in
                            source.next(state)
                        }
                        if let error { throw error }
                        guard result != .error, output.frameLength > 0, let samples = output.floatChannelData?[0] else {
                            throw PackError.invalid("Empty converted sample")
                        }
                        let count = Int(output.frameLength)
                        for i in 0..<count {
                            guard samples[i].isFinite else { throw PackError.invalid("Nonfinite PCM") }
                        }
                        let storage = UnsafeMutablePointer<Float>.allocate(capacity: count)
                        storage.initialize(from: samples, count: count)
                        pcm.append(PCMSample(data: storage, count: count))
                    }
                    var variants: [Int] = []; var ranges: [SampleRange] = []
                    let indexByPath = Dictionary(uniqueKeysWithValues: paths.enumerated().map { ($1, $0) })
                    func indices(_ entries: [String]) throws -> [Int] {
                        try entries.map { entry in
                            guard let index = indexByPath[entry] else { throw PackError.invalid("Unknown sample \(entry)") }
                            return index
                        }
                    }
                    for code in 0..<128 {
                        let m = pack.manifest
                        let name = m.keys[String(code)] ?? m.keyGroups[String(code)] ?? m.fallbackGroup
                        guard let group = m.samples[name] else { throw PackError.invalid("Unknown sample group \(name)") }
                        for entries in [group.down, group.up] {
                            ranges.append(SampleRange(start: variants.count, count: entries.count))
                            variants.append(contentsOf: try indices(entries))
                        }
                    }
                    // Reserved pointer group is optional for older keyboard-only packs.
                    // Missing pointer samples are silent rather than substituting key sounds.
                    for _ in 0..<SoundSlot.pointerButtonCount {
                        for entries in [pack.manifest.samples["pointer"]?.down ?? [], pack.manifest.samples["pointer"]?.up ?? []] {
                            ranges.append(SampleRange(start: variants.count, count: entries.count))
                            variants.append(contentsOf: try indices(entries))
                        }
                    }
                    guard isCurrent() else { throw CancellationError() }
                    let bank = PreparedSoundBank(samples: pcm, variants: variants, ranges: ranges, manifest: pack.manifest)
                    pcm.removeAll() // ownership transferred; defer only frees untransferred data
                    continuation.resume(returning: bank)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

// The loader finishes writing the buffer before this owner is created. The
// converter only reads it; the one mutable flag uses an atomic because the SDK
// marks its synchronous input callback Sendable.
nonisolated private final class ConversionInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let supplied = Atomic<Bool>(false)
    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        if supplied.exchange(true, ordering: .acquiringAndReleasing) {
            status.pointee = .endOfStream; return nil
        }
        status.pointee = .haveData
        return buffer
    }
}
