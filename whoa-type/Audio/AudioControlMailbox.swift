import Synchronization

nonisolated struct AudioControl: @unchecked Sendable {
    nonisolated enum Kind: UInt8, Sendable { case gain = 0, bankTransition = 1, discontinuity = 2 }
    var kind: Kind = .gain
    var gain: Float = 0
    var bank: UnsafeMutablePointer<BankHeader>?
    var sequence: UInt64 = 0
}
nonisolated final class AudioControlMailbox: @unchecked Sendable {
    let commands = SPSCRing<AudioControl>(capacity: 8, empty: AudioControl())
    let acknowledged = Atomic<UInt64>(0)
}
