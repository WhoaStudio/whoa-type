import CoreGraphics

nonisolated struct KeySoundCharacter {
    var gain: Float = 1
    // Position within the pack's pitch range; bounded jitter remains around it.
    var pitchBias: Float = 0
}

nonisolated struct PositionSoundCharacter {
    var pitchCents: Float
    var cutoffHz: Float
    var toneMix: Float
}

nonisolated enum KeyMapper {
    static func positionCharacter(pan: Float) -> PositionSoundCharacter {
        let position = max(-1, min(1, pan / 0.7))
        let unit = (position + 1) * 0.5
        return PositionSoundCharacter(pitchCents: position * 180,
            cutoffHz: 2400 + unit * 8000, toneMix: 0.8 - unit * 0.55)
    }

    // Physical key categories only: no character translation or input history.
    // Called once per trigger, never per output sample.
    static func soundCharacter(_ code: UInt16) -> KeySoundCharacter {
        switch code {
        case 49: return KeySoundCharacter(gain: 1.2, pitchBias: -0.65) // Space
        case 36, 76: return KeySoundCharacter(gain: 1.12, pitchBias: -0.45) // Return
        case 51, 117: return KeySoundCharacter(gain: 1.08, pitchBias: -0.3) // Delete
        case 48: return KeySoundCharacter(gain: 0.98, pitchBias: -0.12) // Tab
        case 54, 55, 56, 58, 59, 60, 61, 62:
            return KeySoundCharacter(gain: 0.86, pitchBias: 0.35)
        case 0, 2, 4, 6, 8, 12, 14, 16, 32, 34, 38, 40, 46:
            return KeySoundCharacter(gain: 0.97, pitchBias: 0.12)
        case 1, 3, 5, 7, 9, 11, 13, 15, 17, 31, 35, 37, 45:
            return KeySoundCharacter(gain: 1.03, pitchBias: -0.12)
        default: return KeySoundCharacter()
        }
    }

    // Horizontal physical key centers, in key units. Static tables are prepared
    // off the event path; unknown/non-keyboard codes are centered.
    static func makePans(_ geometry: KeyboardGeometry) -> [Float] {
        var positions = [Float?](repeating: nil, count: 128)
        let rows: [([Int], Float)] = [
            ([50,18,19,20,21,23,22,26,28,25,29,27,24,51], 0.5),
            ([48,12,13,14,15,17,16,32,34,31,35,33,30,42], 0.75),
            ([57,0,1,2,3,5,4,38,40,37,41,39,36], 0.875),
            ([56,6,7,8,9,11,45,46,43,47,44,60], 1.125),
            ([53,122,120,99,118,96,97,98,100,101,109,103,111], 0.5)
        ]
        for (codes, offset) in rows {
            for (i, code) in codes.enumerated() { positions[code] = Float(i) + offset }
        }
        for (key, x) in [(59,0.75),(58,2.0),(55,3.25),(49,7.0),(54,10.75),(61,12.0),(62,13.0),(123,14.5),(124,16.5),(125,15.5),(126,15.5),(117,15.5),(115,15.5),(119,16.5),(116,16.5),(121,16.5)] { positions[key] = Float(x) }
        if geometry != .ansi { positions[10] = 1.75; positions[42] = 12.75 }
        if geometry == .jis { positions[93] = 12.5; positions[94] = 13.5; positions[95] = 11.5; positions[102] = 4.0; positions[104] = 9.0 }
        return positions.map { x in x.map { max(-0.7, min(0.7, (($0 - 0.5) / 16 * 2 - 1) * 0.7)) } ?? 0 }
    }
    // Device-specific flags distinguish left/right when their aggregate flag
    // remains set. Caps Lock reports a toggle transition rather than a hold.
    static func modifierDown(code: UInt16, flags: UInt64) -> Bool? {
        let mask: UInt64
        switch code {
        case 56: mask = 0x2
        case 60: mask = 0x4
        case 59: mask = 0x1
        case 62: mask = 0x2000
        case 58: mask = 0x20
        case 61: mask = 0x40
        case 55: mask = 0x8
        case 54: mask = 0x10
        case 57: mask = CGEventFlags.maskAlphaShift.rawValue
        default: return nil
        }
        return flags & mask != 0
    }
}
