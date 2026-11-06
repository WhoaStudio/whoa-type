import Combine
import Foundation
import Sparkle

/// Sparkle owns scheduling, preference persistence, verification, and installation.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    @Published private(set) var isConfigured = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var availableVersion: String?
    @Published private(set) var status = "Updates are not configured for this build."
    @Published var automaticallyChecks = true {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
    @Published var automaticallyDownloads = false {
        didSet { controller.updater.automaticallyDownloadsUpdates = automaticallyDownloads }
    }
    @Published var checkInterval: TimeInterval = 86_400 {
        didSet { controller.updater.updateCheckInterval = checkInterval }
    }

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
    )
    private var observations: Set<AnyCancellable> = []
    // The menu bar and Settings retain a visible update action while Sparkle's
    // scheduled alert is behind other applications.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    override init() {
        super.init()
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil else { return }

        let updater = controller.updater
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates
        checkInterval = updater.updateCheckInterval
        observe(updater)
        do {
            try updater.start()
            isConfigured = true
            status = "Ready to check for updates."
            // Sparkle sets up its cycle on the next run loop. A launch check is
            // independent of the interval, but still respects the user's opt-out.
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.automaticallyChecks, updater.canCheckForUpdates else { return }
                updater.checkForUpdatesInBackground()
            }
        } catch {
            status = "Updates could not start: \(error.localizedDescription)"
        }
    }

    func checkForUpdates() {
        guard isConfigured, controller.updater.canCheckForUpdates else { return }
        status = "Checking for updates…"
        controller.checkForUpdates(nil)
    }

    private func observe(_ updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &observations)
        updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] in self?.lastChecked = $0 }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] value in
                guard let self, self.automaticallyChecks != value else { return }
                self.automaticallyChecks = value
            }
            .store(in: &observations)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self] value in
                guard let self, self.automaticallyDownloads != value else { return }
                self.automaticallyDownloads = value
            }
            .store(in: &observations)
        updater.publisher(for: \.updateCheckInterval)
            .sink { [weak self] value in
                guard let self, self.checkInterval != value else { return }
                self.checkInterval = value
            }
            .store(in: &observations)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        status = "Version \(item.displayVersionString) is available."
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        status = "Downloading version \(item.displayVersionString)…"
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        status = "Version \(item.displayVersionString) downloaded. It will be verified before installation."
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        status = "Installing version \(item.displayVersionString)…"
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard let error = error as NSError? else { return }
        if error.domain == SUSparkleErrorDomain && error.code == SUError.noUpdateError.rawValue {
            availableVersion = nil
            status = "You’re up to date."
        } else if (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
                    || (error.domain == SUSparkleErrorDomain && error.code == SUError.installationCanceledError.rawValue) {
            status = "Update cancelled. You can check again later."
        } else if error.domain == SUSparkleErrorDomain
                    && [Int(SUError.signatureError.rawValue), Int(SUError.validationError.rawValue)].contains(error.code) {
            status = "The update could not be verified and was not installed. Please try again later."
        } else if error.domain == SUSparkleErrorDomain && error.code == SUError.downloadError.rawValue {
            status = "The update could not be downloaded. Check your connection and try again."
        } else {
            status = "Update failed. Check your connection and try again. \(error.localizedDescription)"
        }
    }
}
