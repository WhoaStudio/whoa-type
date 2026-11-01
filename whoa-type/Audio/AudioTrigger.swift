import Foundation

nonisolated struct AudioTrigger: Sendable {
    var slot: UInt16 = 0
    var phase: KeyPhase = .down
    var pan: Float = 0
    var gain: Float = 1
}

nonisolated enum SoundSlot {
    static let keyboardCount = 128
    static let pointerButtonCount = 32
    static let count = keyboardCount + pointerButtonCount
}
