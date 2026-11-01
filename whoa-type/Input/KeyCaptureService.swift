import Foundation
import CoreGraphics
import Synchronization

nonisolated final class KeyCaptureService: @unchecked Sendable {
    private let triggers: TriggerRing
    private let held = UnsafeMutablePointer<Bool>.allocate(capacity: 128)
    private let pans = UnsafeMutablePointer<Float>.allocate(capacity: 128)
    private var mouseSoundsEnabled = true
    private var effectsGain: Float = 1
    private var returnDing: (@Sendable () -> Void)?
    private var pointerHeld: UInt32 = 0
    private let recovery = Atomic<Bool>(false)
    private let active = Atomic<Bool>(false)
    private let ready = NSCondition()
    private var loop: CFRunLoop!
    private var thread: Thread!
    // The following fields are owned exclusively by the capture run loop.
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var previewTimers: [CFRunLoopTimer] = []
    private var previewCompletion: CheckedContinuation<Void, Error>?
    private var health: CFRunLoopTimer?
    private var keepAlive: CFRunLoopSource?

    init(triggers: TriggerRing) {
        self.triggers = triggers
        held.initialize(repeating: false, count: 128)
        pans.initialize(repeating: 0, count: 128)
        ready.lock()
        thread = Thread { [self] in run() }
        thread.name = "WhoaType.capture"
        thread.start()
        while loop == nil { ready.wait() }
        ready.unlock()
    }
    var isActive: Bool { active.load(ordering: .acquiring) }
    private func run() {
        ready.lock(); loop = CFRunLoopGetCurrent(); ready.signal(); ready.unlock()
        var context = CFRunLoopSourceContext()
        keepAlive = CFRunLoopSourceCreate(nil, 0, &context)
        CFRunLoopAddSource(loop, keepAlive, .commonModes)
        CFRunLoopRun()
        if let health { CFRunLoopTimerInvalidate(health) }
        if let keepAlive { CFRunLoopSourceInvalidate(keepAlive) }
    }
    private func perform(_ work: @escaping @Sendable () -> Void) {
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(loop)
    }
    func setGeometry(_ geometry: KeyboardGeometry) async {
        let values = KeyMapper.makePans(geometry)
        await withCheckedContinuation { continuation in
            perform { for i in 0..<128 { self.pans[i] = values[i] }; continuation.resume() }
        }
    }
    func configureEffects(mouse: Bool, gain: Double, returnDing: (@Sendable () -> Void)?) async {
        await withCheckedContinuation { continuation in
            perform {
                self.mouseSoundsEnabled = mouse
                self.effectsGain = Float(gain)
                self.returnDing = returnDing
                continuation.resume()
            }
        }
    }
    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            perform {
                self.removeTap()
                guard CGPreflightListenEventAccess() else { continuation.resume(returning: false); return }
                let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                    | (CGEventMask(1) << CGEventType.keyUp.rawValue)
                    | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
                    | PointerMapper.eventMask
                self.tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                    eventsOfInterest: mask, callback: { _, type, event, info in
                        guard let info else { return Unmanaged.passUnretained(event) }
                        let service = Unmanaged<KeyCaptureService>.fromOpaque(info).takeUnretainedValue()
                        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                            service.recovery.store(true, ordering: .releasing)
                        } else { service.receive(type, event) }
                        return Unmanaged.passUnretained(event)
                    }, userInfo: Unmanaged.passUnretained(self).toOpaque())
                guard let tap = self.tap, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
                    self.removeTap(); continuation.resume(returning: false); return
                }
                self.source = source
                self.held[57] = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
                CFRunLoopAddSource(self.loop, source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                self.active.store(true, ordering: .releasing)
                self.health = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 1, 1, 0, 0) { [weak self] _ in self?.checkHealth() }
                CFRunLoopAddTimer(self.loop, self.health, .commonModes)
                continuation.resume(returning: true)
            }
        }
    }
    @inline(__always) private func receive(_ type: CGEventType, _ event: CGEvent) {
        guard active.load(ordering: .relaxed) else { return }
        switch type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            if var trigger = PointerMapper.trigger(type: type,
                button: event.getIntegerValueField(.mouseEventButtonNumber), held: &pointerHeld) {
                if mouseSoundsEnabled {
                    trigger.gain = effectsGain
                    _ = triggers.push(trigger)
                }
            }
            return
        default: break
        }
        let raw = event.getIntegerValueField(.keyboardEventKeycode)
        guard raw >= 0, raw <= Int64(UInt16.max) else { return }
        let code = UInt16(min(raw, 127)); let i = Int(code)
        let down: Bool
        if type == .flagsChanged {
            guard let value = KeyMapper.modifierDown(code: code, flags: event.flags.rawValue), value != held[i] else { return }
            down = value
        } else if type == .keyDown {
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0, !held[i] else { return }
            down = true
        } else if type == .keyUp {
            guard held[i] else { return }
            down = false
        } else { return }
        held[i] = down
        if down && (code == 36 || code == 76) { returnDing?() }
        _ = triggers.push(AudioTrigger(slot: code, phase: down ? .down : .up, pan: pans[i]))
    }
    private func checkHealth() {
        guard tap != nil else { return }
        guard CGPreflightListenEventAccess() else { removeTap(); return }
        if recovery.exchange(false, ordering: .acquiringAndReleasing) {
            // Lost observation creates a discontinuity. Stop and let the
            // coordinator clear the renderer before bounded restart attempts.
            removeTap()
        }
    }
    private func removeTap() {
        active.store(false, ordering: .releasing)
        if let health { CFRunLoopTimerInvalidate(health) }
        health = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(loop, source, .commonModes) }
        tap = nil; source = nil
        for i in 0..<128 { held[i] = false }
        pointerHeld = 0
        recovery.store(false, ordering: .releasing)
    }
    func pause() async {
        await withCheckedContinuation { continuation in
            perform { self.removeTap(); self.cancelPreviewOnLoop(); continuation.resume() }
        }
    }
    func cancelPreview() { perform { self.cancelPreviewOnLoop() } }
    private func cancelPreviewOnLoop() {
        for timer in previewTimers { CFRunLoopTimerInvalidate(timer) }
        previewTimers.removeAll()
        let completion = previewCompletion; previewCompletion = nil
        completion?.resume(throwing: CancellationError())
    }
    func preview(_ events: [SoundPackManifest.PreviewEvent]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            perform {
                self.removeTap(); self.cancelPreviewOnLoop()
                self.previewCompletion = continuation
                let start = CFAbsoluteTimeGetCurrent() + 0.02
                for (index, event) in events.enumerated() {
                    let timer = CFRunLoopTimerCreateWithHandler(nil, start + Double(event.atMs) / 1000, 0, 0, index) { [self] _ in
                        let pointer = Int(event.keyCode) >= SoundSlot.keyboardCount
                        _ = triggers.push(AudioTrigger(slot: event.keyCode, phase: event.phase,
                            pan: pointer ? 0 : pans[Int(event.keyCode)], gain: pointer ? effectsGain : 1))
                    }!
                    self.previewTimers.append(timer); CFRunLoopAddTimer(self.loop, timer, .commonModes)
                }
                let end = Double(events.last?.atMs ?? 0) / 1000 + 0.7
                let timer = CFRunLoopTimerCreateWithHandler(nil, start + end, 0, 0, 0) { [self] _ in
                    let completion = previewCompletion; previewCompletion = nil
                    for timer in previewTimers { CFRunLoopTimerInvalidate(timer) }
                    previewTimers.removeAll(); completion?.resume()
                }!
                self.previewTimers.append(timer); CFRunLoopAddTimer(self.loop, timer, .commonModes)
            }
        }
    }
    func shutdown() async {
        await pause()
        await withCheckedContinuation { continuation in
            perform { CFRunLoopStop(self.loop); continuation.resume() }
        }
    }
    deinit { held.deinitialize(count: 128); held.deallocate(); pans.deinitialize(count: 128); pans.deallocate() }
    // The app owns this service for its process lifetime. Callback userInfo stays
    // valid until shutdown removes the tap on this thread.
}
