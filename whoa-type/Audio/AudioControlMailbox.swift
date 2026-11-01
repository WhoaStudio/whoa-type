import Synchronization

nonisolated struct AudioControl: @unchecked Sendable {
    // 0 gain, 1 bank transition, 2 discontinuity
    var kind: UInt8 = 0
    var gain: Float = 0
    var bank: UnsafeMutablePointer<BankHeader>?
    var sequence: UInt64 = 0
}
nonisolated final class AudioControlMailbox: @unchecked Sendable {
    let commands = SPSCRing<AudioControl>(capacity: 8, empty: AudioControl())
    let acknowledged = Atomic<UInt64>(0)
}
