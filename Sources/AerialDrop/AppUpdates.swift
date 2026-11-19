import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdates: NSObject, SPUUpdaterDelegate {
    private let model: AppModel
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var availabilityObservation: NSKeyValueObservation?

    private(set) var isConfigured = false
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var isInstallingUpdate = false

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard controller == nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller
        availabilityObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshCheckAvailability()
            }
        }
        controller.startUpdater()
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        refreshCheckAvailability()
        isConfigured = true
    }

    func checkForUpdates() {
        guard let controller, controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        deferRelaunchIfBusy { installHandler() }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        isInstallingUpdate = true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        isInstallingUpdate = false
    }

    /// Sparkle can finish downloading while an import or catalogue operation is running.
    /// Observe the model so the authorized restart can proceed even with all windows closed.
    func deferRelaunchIfBusy(_ resume: @escaping @MainActor () -> Void) -> Bool {
        guard hasActiveOperation else { return false }
        _ = withObservationTracking {
            hasActiveOperation
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.deferRelaunchIfBusy(resume) else { return }
                resume()
            }
        }
        return true
    }

    private var hasActiveOperation: Bool {
        model.isWorking || model.catalogueRefreshState == .refreshing
    }

    private func refreshCheckAvailability() {
        canCheckForUpdates = controller?.updater.canCheckForUpdates ?? false
    }
}
