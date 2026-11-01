import Foundation
import Testing
@testable import WhoaTypeCore

@MainActor struct SettingsTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "WhoaTypeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
    @Test func onboardingCompletionPersists() {
        withDefaults { defaults in
            let first = SettingsStore(defaults: defaults)
            #expect(!first.onboardingCompleted)
            #expect(!SettingsStore(defaults: defaults).onboardingCompleted)
            first.onboardingCompleted = true
            #expect(SettingsStore(defaults: defaults).onboardingCompleted)
            defaults.set(false, forKey: "onboardingCompleted")
            #expect(!SettingsStore(defaults: defaults).onboardingCompleted)
        }
    }
    @Test func existingInstallSkipsOnboarding() {
        withDefaults { defaults in
            defaults.set(1, forKey: "settingsVersion")
            #expect(SettingsStore(defaults: defaults).onboardingCompleted)
        }
    }
    @Test func firstRunRequiresOptIn() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, validPackIDs: ["one"])
            #expect(!store.soundEnabled)
            #expect(store.volume == 0.5)
            #expect(store.selectedPackID == "one")
            #expect(store.keyboardGeometry == .ansi)
            #expect(defaults.integer(forKey: "settingsVersion") == 1)
        }
    }
    @Test func invalidPreferencesAreRepaired() {
        withDefaults { defaults in
            defaults.set(5.0, forKey: "volume")
            defaults.set("missing", forKey: "selectedPackID")
            defaults.set("bad", forKey: "keyboardGeometry")
            let store = SettingsStore(defaults: defaults, validPackIDs: ["one"])
            #expect(store.volume == 1)
            #expect(store.selectedPackID == "one")
            #expect(store.keyboardGeometry == .ansi)
            store.volume = -.infinity
            #expect(store.volume == 0.5)
            store.volume = -2
            #expect(store.volume == 0)
            #expect(defaults.double(forKey: "volume") == 0)
        }
    }
    @Test func preferencesRoundTrip() {
        withDefaults { defaults in
            let first = SettingsStore(defaults: defaults, validPackIDs: ["one", "two"])
            first.soundEnabled = true
            first.volume = 0.75
            first.keyboardGeometry = .jis
            first.selectedPackID = "two"
            let second = SettingsStore(defaults: defaults, validPackIDs: ["one", "two"])
            #expect(second.soundEnabled)
            #expect(second.volume == 0.75)
            #expect(second.keyboardGeometry == .jis)
            #expect(second.selectedPackID == "two")
        }
    }
    @Test func soundEffectsPreferencesPersistAndClamp() {
        withDefaults { defaults in
            let first = SettingsStore(defaults: defaults)
            #expect(first.mouseSoundsEnabled)
            #expect(!first.returnDingEnabled)
            #expect(first.effectsVolume == 1)
            first.mouseSoundsEnabled = false
            first.returnDingEnabled = true
            first.effectsVolume = 0.3
            let restored = SettingsStore(defaults: defaults)
            #expect(!restored.mouseSoundsEnabled)
            #expect(restored.returnDingEnabled)
            #expect(restored.effectsVolume == 0.3)
            restored.effectsVolume = 4
            #expect(restored.effectsVolume == 1)
            restored.effectsVolume = -.infinity
            #expect(restored.effectsVolume == 0.5)
        }
    }
    @Test func effectiveSoundRequiresAllGates() {
        #expect(AppState.resolve(enabled: false, authorized: true, audioReady: true, captureActive: true) == .soundOff)
        #expect(AppState.resolve(enabled: true, authorized: false, audioReady: true, captureActive: true) == .permissionRequired)
        #expect(AppState.resolve(enabled: true, authorized: true, audioReady: false, captureActive: true) == .preparingAudio)
        #expect(AppState.resolve(enabled: true, authorized: true, audioReady: true, captureActive: false) == .captureUnavailable)
        #expect(AppState.resolve(enabled: true, authorized: true, audioReady: true, captureActive: true) == .ready)
    }
}
