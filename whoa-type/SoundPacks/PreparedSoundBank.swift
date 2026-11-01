import Foundation

nonisolated struct PCMSample {
    var data: UnsafeMutablePointer<Float>?
    var count: Int = 0
}
nonisolated struct SampleRange { var start: Int = 0; var count: Int = 0 }
// Immutable after loader publication. The audio-control queue retains the owner;
// the renderer borrows only the plain header and its pointees.
nonisolated struct BankHeader {
    var samples: UnsafeMutablePointer<PCMSample>
    var variants: UnsafeMutablePointer<Int>
    var ranges: UnsafeMutablePointer<SampleRange> // physical-key/button slots, two phases
    var slotCount: Int
    var gain: Float
    var minCents: Float
    var maxCents: Float
}
nonisolated final class PreparedSoundBank: @unchecked Sendable {
    let header: UnsafeMutablePointer<BankHeader>
    private let sampleCount: Int
    private let variantCount: Int
    private let rangeCount: Int
    convenience init(pcm: [[Float]], variants: [Int], ranges: [SampleRange], manifest: SoundPackManifest) {
        let samples = pcm.map { values in
            let data = UnsafeMutablePointer<Float>.allocate(capacity: values.count)
            data.initialize(from: values, count: values.count)
            return PCMSample(data: data, count: values.count)
        }
        self.init(samples: samples, variants: variants, ranges: ranges, manifest: manifest)
    }
    // Takes ownership of sample data allocated by the loader, avoiding a second
    // full candidate-bank copy while the previous bank is still retained.
    init(samples owned: [PCMSample], variants: [Int], ranges: [SampleRange], manifest: SoundPackManifest) {
        precondition(ranges.count % 2 == 0 && ranges.count <= SoundSlot.count * 2)
        sampleCount = owned.count; variantCount = variants.count; rangeCount = ranges.count
        let samples = UnsafeMutablePointer<PCMSample>.allocate(capacity: owned.count)
        samples.initialize(from: owned, count: owned.count)
        let indices = UnsafeMutablePointer<Int>.allocate(capacity: variants.count)
        indices.initialize(from: variants, count: variants.count)
        let lookup = UnsafeMutablePointer<SampleRange>.allocate(capacity: ranges.count)
        lookup.initialize(from: ranges, count: ranges.count)
        header = .allocate(capacity: 1)
        header.initialize(to: BankHeader(samples: samples, variants: indices, ranges: lookup, slotCount: ranges.count / 2,
            gain: pow(10, manifest.gainDB / 20), minCents: manifest.pitchCents.min, maxCents: manifest.pitchCents.max))
    }
    deinit {
        for i in 0..<sampleCount { header.pointee.samples[i].data?.deallocate() }
        header.pointee.samples.deinitialize(count: sampleCount); header.pointee.samples.deallocate()
        header.pointee.variants.deinitialize(count: variantCount); header.pointee.variants.deallocate()
        header.pointee.ranges.deinitialize(count: rangeCount); header.pointee.ranges.deallocate()
        header.deinitialize(count: 1); header.deallocate()
    }
}
