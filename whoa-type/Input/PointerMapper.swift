import CoreGraphics

nonisolated enum PointerMapper {
    static var eventMask: CGEventMask {
        (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
        | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
        | (CGEventMask(1) << CGEventType.rightMouseUp.rawValue)
        | (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
        | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
    }
    // Tracks only transient button holds. Never reads cursor position, pressure,
    // target windows, gesture data, click counts, or text.
    static func trigger(type: CGEventType, button: Int64, held: inout UInt32) -> AudioTrigger? {
        let index: Int
        let down: Bool
        switch type {
        case .leftMouseDown: index = 0; down = true
        case .leftMouseUp: index = 0; down = false
        case .rightMouseDown: index = 1; down = true
        case .rightMouseUp: index = 1; down = false
        case .otherMouseDown, .otherMouseUp:
            guard button >= 2, button < Int64(SoundSlot.pointerButtonCount) else { return nil }
            index = Int(button); down = type == .otherMouseDown
        default: return nil
        }
        let bit = UInt32(1) << index
        guard (held & bit != 0) != down else { return nil }
        if down { held |= bit } else { held &= ~bit }
        return AudioTrigger(slot: UInt16(SoundSlot.keyboardCount + index), phase: down ? .down : .up, pan: 0)
    }
}
