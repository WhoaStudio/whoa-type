import AVFoundation
import AppKit
import Carbon
import Observation
import os

@MainActor @Observable
final class AppCoordinator {
    var settings = SettingsStore()
    let permission = PermissionController()
    let loginItem = LoginItemService()
    let updater = UpdateController()
    var hotkey = SoundHotkey()
    private var introWindow: IntroWindowController?
    private var settingsWindow: SettingsWindowController?

    func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(coordinator: self) }
        settingsWindow?.present()
    }
    private(set) var packs: [SoundPack] = []
    private(set) var audioReady = false
    private(set) var captureActive = false
    private(set) var previewing: String?
    private(set) var errorMessage: String?
    private(set) var loading = false
    private(set) var audioRoute: AudioRoute?
    private var routeChangedWhileBusy = false
    private let audio: AudioService
    private let capture: KeyCaptureService
    private let repository = SoundPackRepository()
    private let requests: PreviewController
    private var installedID: String?
    private var bankCache = BankCache<PreparedSoundBank>()
    private var sleeping = false
    private var quitting = false
    private var busy = false
    private var recoveryAttempts = 0
    private var healthTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    // Lifecycle diagnostics only; never log input data.
    private let log = Logger(subsystem: "studio.whoa.type", category: "lifecycle")
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var dingSound: NSSound?
    // Signalled from the capture thread without allocating; coalesces bursts onto the main queue.
    private let dingSignal = DispatchSource.makeUserDataAddSource(queue: .main)
    private var lastSettings = SettingsSnapshot(
        enabled: false, volume: 0.5, geometry: .ansi,
        effectsVolume: 1, mouseSounds: true, returnDing: false)

    var state: AppState {
        if let errorMessage { return .audioUnavailable(errorMessage) }
        return .resolve(
            enabled: settings.soundEnabled, authorized: permission.authorized,
            audioReady: audioReady, captureActive: captureActive)
    }
    var statusMessage: String {
        if let previewing { return "Previewing \(previewing)…" }
        if loading { return "Loading switches…" }
        return state.message
    }
    init() {
        let audio = AudioService()
        self.audio = audio
        let capture = KeyCaptureService(triggers: audio.triggers)
        self.capture = capture
        requests = PreviewController(capture: capture)
        lastSettings = settings.snapshot
        hotkey.onPress = { [weak self] in self?.settings.soundEnabled.toggle() }
        dingSignal.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.settings.soundEnabled, self.settings.returnDingEnabled else {
                    return
                }
                self.previewDing()
            }
        }
        dingSignal.resume()
        observeSettings()
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.audioReady else { return }
                    if self.busy {
                        self.routeChangedWhileBusy = true
                    } else {
                        self.submit(.rebuild)
                    }
                }
            })
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspace.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleeping = true
                    self?.submit(.reconcile)
                }
            })
        workspaceObservers.append(
            workspace.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleeping = false
                    self?.recoveryAttempts = 0
                    self?.submit(.rebuild)
                }
            })
        startupTask = Task { await bootstrap() }
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self else { return }
                if self.capture.isActive { self.recoveryAttempts = 0 }
                if self.quitting || self.busy || self.sleeping || !self.settings.soundEnabled {
                    continue
                }
                let wasAuthorized = self.permission.authorized
                self.permission.refresh()
                var engineRunning = true
                if self.audioReady { engineRunning = await self.audio.isRunning() }
                switch HealthAction.decide(
                    soundEnabled: self.settings.soundEnabled, engineRunning: engineRunning,
                    wasAuthorized: wasAuthorized, authorized: self.permission.authorized,
                    captureActive: self.capture.isActive, hasError: self.errorMessage != nil,
                    retries: self.recoveryAttempts)
                {
                case .rebuild: self.submit(.rebuild)
                case .reconcile: self.submit(.reconcile)
                case .retryCapture:
                    self.recoveryAttempts += 1
                    self.submit(.reconcile)
                case .giveUp: self.captureActive = false
                case .none: break
                }
            }
        }
    }
    private func observeSettings() {
        withObservationTracking {
            _ = settings.soundEnabled
            _ = settings.volume
            _ = settings.keyboardGeometry
            _ = settings.effectsVolume
            _ = settings.mouseSoundsEnabled
            _ = settings.returnDingEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Re-arm first and decide synchronously, so changes made while we await below
                // (a slider drag, say) are neither missed nor applied out of order.
                self.observeSettings()
                let current = self.settings.snapshot
                let changes = current.changes(from: self.lastSettings)
                self.lastSettings = current
                if changes.volume { self.audio.setGain(current.volume) }
                if changes.effects { await self.configureEffects() }
                if changes.lifecycle {
                    self.recoveryAttempts = 0
                    self.submit(.reconcile)
                }
            }
        }
    }
    private func bootstrap() async {
        if !settings.onboardingCompleted && introWindow == nil {
            introWindow = IntroWindowController(coordinator: self)
            introWindow?.showWindow(nil)
            NSApplication.shared.activate()
        }
        loading = true
        do {
            guard let resource = Bundle.main.resourceURL else {
                throw PackError.invalid("Bundle resources unavailable")
            }
            // A blue folder resource preserves each pack's manifest/sample paths.
            packs = try await repository.discover(in: resource.appendingPathComponent("SoundPacks"))
            if !packs.contains(where: { $0.id == settings.selectedPackID }) {
                settings.selectedPackID = packs[0].id
            }
            loading = false
            submit(.reconcile)
        } catch {
            loading = false
            errorMessage = error.localizedDescription
            log.error("Pack discovery failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    private func configureEffects() async {
        var callback: (@Sendable () -> Void)?
        if settings.returnDingEnabled {
            let signal = dingSignal
            callback = { signal.add(data: 1) }
        }
        await capture.configureEffects(
            mouse: settings.mouseSoundsEnabled, gain: settings.effectsVolume, returnDing: callback)
    }
    func previewDing() {
        dingSound?.stop()
        dingSound = NSSound(named: "Glass")?.copy() as? NSSound
        dingSound?.volume = Float(settings.effectsVolume * settings.volume)
        dingSound?.play()
    }
    func previewMouse() { submit(.previewMouse) }
    func select(_ id: String) { submit(.select(id)) }
    func preview(_ id: String) { submit(.preview(id)) }
    func previewKey() { submit(.previewKey(settings.selectedPackID)) }
    func selectAndPreview(_ id: String) { submit(.selectAndPreview(id)) }
    private func submit(_ request: PreviewController.Request) {
        guard !quitting else { return }
        requests.submit(request) { [weak self] request, revision in
            await self?.perform(request, revision: revision)
        }
    }
    private func ensurePack(_ id: String, revision: UInt64) async throws {
        guard let pack = packs.first(where: { $0.id == id }) else {
            throw PackError.invalid("Selected pack is unavailable")
        }
        let rate = try await audio.prepare()
        audio.setGain(settings.volume)
        if installedID != id {
            loading = true
            defer { loading = false }
            let generation = requests.generation
            let bank: PreparedSoundBank
            if let cached = bankCache.bank(for: id, rate: rate) {
                bank = cached
            } else {
                bank = try await repository.load(
                    pack, rate: rate, isCurrent: { generation.matches(revision) })
            }
            guard generation.matches(revision) else { throw CancellationError() }
            await capture.pause()
            captureActive = false
            try await audio.install(bank)
            installedID = id
            bankCache.store(bank, id: id, rate: rate, keeping: settings.selectedPackID)
        }
        audioRoute = await audio.outputRoute()
        audioReady = true
    }
    private func perform(_ request: PreviewController.Request, revision: UInt64) async {
        busy = true
        defer {
            busy = false
            if routeChangedWhileBusy {
                routeChangedWhileBusy = false
                if !quitting && !sleeping { submit(.rebuild) }
            }
        }
        errorMessage = nil
        let priorID = settings.selectedPackID
        do {
            if case .rebuild = request {
                await capture.pause()
                captureActive = false
                if audioReady { try? await audio.reset() }
                await audio.stop()
                installedID = nil
                audioReady = false
            }
            if sleeping || quitting {
                await capture.pause()
                captureActive = false
                if audioReady { try? await audio.reset() }
                await audio.stop()
                audioReady = false
                installedID = nil
                return
            }
            await configureEffects()
            await capture.setGeometry(settings.keyboardGeometry)
            switch request {
            case .select(let id):
                try await ensurePack(id, revision: revision)
                guard requests.generation.matches(revision) else { throw CancellationError() }
                settings.selectedPackID = id  // commit only after successful swap
            case .preview(let id), .previewKey(let id), .selectAndPreview(let id):
                await capture.pause()
                captureActive = false
                if audioReady { try await audio.reset() }
                guard let pack = packs.first(where: { $0.id == id }) else {
                    throw PackError.invalid("Preview pack unavailable")
                }
                try await ensurePack(id, revision: revision)
                guard requests.generation.matches(revision) else { throw CancellationError() }
                if case .selectAndPreview = request { settings.selectedPackID = id }
                previewing = pack.name
                let events: [SoundPackManifest.PreviewEvent]
                if case .previewKey = request {
                    events = [
                        .init(atMs: 0, keyCode: 0, phase: .down),
                        .init(atMs: 100, keyCode: 0, phase: .up),
                    ]
                } else {
                    events = pack.manifest.preview
                }
                do { try await capture.preview(events) } catch is CancellationError {}  // latest request cancels remaining synthetic events
                previewing = nil
                try await ensurePack(settings.selectedPackID, revision: revision)
            case .previewMouse:
                await capture.pause()
                captureActive = false
                try await ensurePack(settings.selectedPackID, revision: revision)
                if audioReady { try await audio.reset() }
                try await capture.preview([
                    .init(atMs: 0, keyCode: 128, phase: .down),
                    .init(atMs: 100, keyCode: 128, phase: .up),
                ])
            case .reconcile, .rebuild: break
            }
            guard requests.generation.matches(revision) else { throw CancellationError() }
            permission.refresh()
            await capture.pause()
            captureActive = false
            if audioReady { try await audio.reset() }
            if settings.soundEnabled && permission.authorized {
                try await ensurePack(settings.selectedPackID, revision: revision)
                captureActive = await capture.start()
            } else {
                await audio.stop()
                audioReady = false
                installedID = nil
            }
        } catch is CancellationError {
            previewing = nil
            loading = false
            await capture.pause()
            captureActive = false
            if audioReady { try? await audio.reset() }
            await audio.stop()
            audioReady = false
            installedID = nil
        } catch {
            previewing = nil
            loading = false
            errorMessage = error.localizedDescription
            log.error("Audio or pack failure: \(error.localizedDescription, privacy: .public)")
            await capture.pause()
            captureActive = false
            // Failed candidate loads leave the current bank retained and the saved
            // selection untouched. Clear voices, and stop if no live bank remains.
            if audioReady { try? await audio.reset() }
            if installedID != priorID || !settings.soundEnabled {
                await audio.stop()
                audioReady = false
                installedID = nil
            } else if permission.authorized {
                captureActive = await capture.start()
            }
        }
    }
    func refresh() {
        permission.refresh()
        loginItem.refresh()
        recoveryAttempts = 0
        if packs.isEmpty {
            if !loading { startupTask = Task { await bootstrap() } }
        } else {
            submit(.reconcile)
        }
    }
    func quit() {
        guard !quitting else { return }
        quitting = true
        healthTask?.cancel()
        hotkey.invalidate()
        Task {
            await requests.shutdown()
            await startupTask?.value
            await capture.pause()
            if audioReady { try? await audio.reset() }
            await audio.stop()
            await capture.shutdown()
            NSApplication.shared.terminate(nil)
        }
    }
}

/// Carbon registers only the configured combination, without monitoring other keystrokes.
@MainActor @Observable
final class SoundHotkey {
    static let keys: [(String, UInt32)] = [("K", 40), ("S", 1), ("M", 46), ("Space", 49)]
    var enabled = UserDefaults.standard.bool(forKey: "hotkey.enabled") { didSet { register() } }
    var modifierChoice = UserDefaults.standard.integer(forKey: "hotkey.modifiers") {
        didSet { register() }
    }
    var keyChoice = UserDefaults.standard.integer(forKey: "hotkey.key") { didSet { register() } }
    private(set) var message: String?
    var onPress: (() -> Void)?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init() {
        var event = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let hotkey = Unmanaged<SoundHotkey>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { hotkey.onPress?() }
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        register()
    }

    /// Unregisters the hotkey and removes the Carbon handler, which holds an unretained pointer to `self`.
    func invalidate() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        onPress = nil
    }

    private func register() {
        guard handler != nil else { return }
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: "hotkey.enabled")
        defaults.set(modifierChoice, forKey: "hotkey.modifiers")
        defaults.set(keyChoice, forKey: "hotkey.key")
        message = nil
        guard enabled else { return }
        let modifiers: UInt32
        switch modifierChoice {
        case 1: modifiers = UInt32(controlKey | optionKey | cmdKey)
        case 2: modifiers = UInt32(shiftKey | cmdKey)
        default: modifiers = UInt32(controlKey | optionKey)
        }
        let index = Self.keys.indices.contains(keyChoice) ? keyChoice : 0
        let result = RegisterEventHotKey(
            Self.keys[index].1, modifiers,
            EventHotKeyID(signature: 0x5748_5459, id: 1), GetApplicationEventTarget(), 0, &reference
        )
        message =
            result == noErr
            ? "Toggles sounds while any app is active."
            : "This shortcut is unavailable. Choose another combination."
    }
}
