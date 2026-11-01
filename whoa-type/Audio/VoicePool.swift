import Foundation

nonisolated struct Voice {
    var sample = PCMSample()
    var cursor: Double = 0
    var increment: Double = 1
    var left: Float = 0
    var right: Float = 0
    var toneCoefficient: Float = 1
    var toneMix: Float = 0
    var toneState: Float = 0
    var age: UInt64 = 0
    var lastLeft: Float = 0
    var lastRight: Float = 0
    var tailLeft: Float = 0
    var tailRight: Float = 0
    var tailFrames: Int = 0
    var active = false
}
nonisolated enum VoicePool {
    static let capacity = 64
    static func replacement(_ voices: UnsafeMutablePointer<Voice>) -> Int {
        var choice = 0
        for i in 0..<capacity {
            if !voices[i].active { return i }
            let amplitude = abs(voices[i].lastLeft) + abs(voices[i].lastRight)
            let best = abs(voices[choice].lastLeft) + abs(voices[choice].lastRight)
            if amplitude < best || (amplitude == best && voices[i].age < voices[choice].age) { choice = i }
        }
        return choice
    }
}
