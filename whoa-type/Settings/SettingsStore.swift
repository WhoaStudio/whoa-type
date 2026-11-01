import Foundation
import Observation

@MainActor @Observable
final class SettingsStore {
    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: "onboardingCompleted") } }
    private let defaults: UserDefaults
    var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "soundEnabled") } }
    var mouseSoundsEnabled: Bool { didSet { defaults.set(mouseSoundsEnabled, forKey: "mouseSoundsEnabled") } }
    var returnDingEnabled: Bool { didSet { defaults.set(returnDingEnabled, forKey: "returnDingEnabled") } }
    var effectsVolume: Double {
        didSet {
            let validated = Self.validVolume(effectsVolume)
            if effectsVolume != validated { effectsVolume = validated }
            defaults.set(validated, forKey: "effectsVolume")
        }
    }
    var volume: Double {
        didSet {
            let validated = Self.validVolume(volume)
            if volume != validated { volume = validated }
            defaults.set(validated, forKey: "volume")
        }
    }
    var selectedPackID: String { didSet { defaults.set(selectedPackID, forKey: "selectedPackID") } }
    var keyboardGeometry: KeyboardGeometry { didSet { defaults.set(keyboardGeometry.rawValue, forKey: "keyboardGeometry") } }

    init(defaults: UserDefaults = .standard, validPackIDs: [String] = []) {
        self.defaults = defaults
        onboardingCompleted = defaults.object(forKey: "onboardingCompleted") as? Bool ?? (defaults.object(forKey: "settingsVersion") != nil)
        mouseSoundsEnabled = defaults.object(forKey: "mouseSoundsEnabled") as? Bool ?? true
        returnDingEnabled = defaults.bool(forKey: "returnDingEnabled")
        effectsVolume = Self.validVolume(defaults.object(forKey: "effectsVolume") as? Double ?? 1)
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? false
        volume = Self.validVolume(defaults.object(forKey: "volume") as? Double ?? 0.5)
        let saved = defaults.string(forKey: "selectedPackID") ?? ""
        selectedPackID = validPackIDs.isEmpty ? saved : (validPackIDs.contains(saved) ? saved : validPackIDs[0])
        keyboardGeometry = KeyboardGeometry(rawValue: defaults.string(forKey: "keyboardGeometry") ?? "") ?? .ansi
        defaults.set(onboardingCompleted, forKey: "onboardingCompleted")
        defaults.set(1, forKey: "settingsVersion")
        defaults.set(volume, forKey: "volume")
        defaults.set(selectedPackID, forKey: "selectedPackID")
        defaults.set(keyboardGeometry.rawValue, forKey: "keyboardGeometry")
        // Remove preferences from the superseded starter implementation.
        for key in ["sound.enabled", "sound.volume", "sound.effect", "sound.output", "notifications.requested"] {
            defaults.removeObject(forKey: key)
        }
    }

    private static func validVolume(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0.5
    }
}
