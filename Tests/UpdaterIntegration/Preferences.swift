// Compiled with the production UpdateController by scripts/test-updater.sh.
import AppKit
import Sparkle

@main
struct UpdaterPreferencesCheck {
    @MainActor static func main() {
        let defaults = UserDefaults.standard
        let phase = CommandLine.arguments.last!
        if phase == "write" {
            defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        }
        let controller = UpdateController()
        precondition(controller.isConfigured, controller.status)
        if phase == "write" {
            precondition(controller.automaticallyChecks)
            precondition(!controller.automaticallyDownloads)
            precondition(controller.checkInterval == 86_400)
            controller.automaticallyChecks = false
            controller.automaticallyDownloads = true
            controller.checkInterval = 604_800
            defaults.set(Date(timeIntervalSince1970: 1_700_000_000), forKey: "SULastCheckTime")
        } else if phase == "read" {
            precondition(!controller.automaticallyChecks)
            precondition(controller.automaticallyDownloads)
            precondition(controller.checkInterval == 604_800)
            precondition(controller.lastChecked == Date(timeIntervalSince1970: 1_700_000_000))
            controller.automaticallyChecks = true
            controller.automaticallyDownloads = false
            controller.checkInterval = 2_592_000
        } else {
            precondition(controller.automaticallyChecks)
            precondition(!controller.automaticallyDownloads)
            precondition(controller.checkInterval == 2_592_000)
            defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        }
        // These invoke the production delegate with representative Sparkle errors.
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
        controller.updater(updater, didFinishUpdateCycleFor: .updates,
                           error: NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue)))
        precondition(controller.status == "You’re up to date.")
        controller.updater(updater, didFinishUpdateCycleFor: .updates,
                           error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        precondition(controller.status.contains("Check your connection"))
        controller.updater(updater, didFinishUpdateCycleFor: .updates,
                           error: NSError(domain: SUSparkleErrorDomain, code: Int(SUError.downloadError.rawValue)))
        precondition(controller.status.contains("could not be downloaded"))
        controller.updater(updater, didFinishUpdateCycleFor: .updates,
                           error: NSError(domain: SUSparkleErrorDomain, code: Int(SUError.signatureError.rawValue)))
        precondition(controller.status.contains("was not installed"))
        // Flush the preferences before the next separate process reads them.
        defaults.synchronize()
        print("Updater preferences and status checks passed (\(phase)).")
    }
}
