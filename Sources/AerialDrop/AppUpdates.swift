import Darwin
import Foundation
import Observation
import OSLog
import Sparkle

@MainActor
@Observable
final class AppUpdates: NSObject, SPUUpdaterDelegate {
    private let model: AppModel
    private let defaults: UserDefaults
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var availabilityObservation: NSKeyValueObservation?
    @ObservationIgnored private var signedAppcastLoaded = false
    private var interaction: UpdateInteraction {
        didSet {
            if interaction.recoveredOffer != oldValue.recoveredOffer {
                AppPreferences.setRecoveredUpdateOffer(interaction.recoveredOffer, defaults: defaults)
            }
        }
    }

    let isConfigured: Bool
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var isInstallingUpdate = false

    var availableVersion: String? { isConfigured ? interaction.offer?.version : nil }
    var progressDescription: LocalizedStringResource? { interaction.activity?.description }
    var message: LocalizedStringResource? { interaction.feedback?.description }
    var canInstallUpdate: Bool {
        interaction.offer != nil && interaction.activity == nil && canCheckForUpdates
    }

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        isConfigured = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String
            && Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String
            && (Bundle.main.object(forInfoDictionaryKey: "SUAllowsAutomaticUpdates") as? Bool) == false
        let savedOffer = AppPreferences.recoveredUpdateOffer(defaults: defaults)
        let recoveredOffer = savedOffer.flatMap {
            UpdateInteraction.isBuild($0.build, newerThan: AppVersion.buildNumber) ? $0 : nil
        }
        interaction = UpdateInteraction(recoveredOffer: recoveredOffer)
        if savedOffer != recoveredOffer {
            AppPreferences.setRecoveredUpdateOffer(nil, defaults: defaults)
        }
    }

    func start() {
        guard isConfigured, updater == nil else { return }

        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: InlineUpdateDriver(owner: self),
            delegate: self
        )
        do {
            try updater.start()
        } catch {
            Logger(subsystem: "com.yapwh.aerialdrop", category: "Updates")
                .error("Could not start the updater: \(error.localizedDescription)")
            return
        }

        self.updater = updater
        availabilityObservation = updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshCheckAvailability()
            }
        }
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        refreshCheckAvailability()
    }

    func checkForUpdates() {
        guard let updater = idleUpdater else { return }
        interaction.beginCheck()
        updater.checkForUpdates()
    }

    func installAvailableUpdate() {
        guard let updater = idleUpdater, interaction.offer != nil,
              interaction.beginInstall(canInstallInPlace: Self.canInstallInPlace()) else { return }
        updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }

    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool {
        false
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        // Sparkle does not call this delegate method when it resumes an installer or download.
        signedAppcastLoaded = appcast.signingValidationStatus == .succeeded
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        let postponed = deferRelaunchIfBusy { installHandler() }
        if postponed { interaction.advance(to: .waitingForWork) }
        return postponed
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        isInstallingUpdate = true
        interaction.advance(to: .relaunching)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        isInstallingUpdate = false
        let sparkleError = error as NSError?
        let noUpdate = sparkleError?.domain == SUSparkleErrorDomain
            && sparkleError?.code == Int(SUError.noUpdateError.rawValue)
        if noUpdate {
            interaction.reportedMissingUpdate(userInitiated: updateCheck == .updates, fromSignedAppcast: signedAppcastLoaded)
        }
        signedAppcastLoaded = false
        interaction.finish(failed: error != nil && !noUpdate)
        refreshCheckAvailability()
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
        canCheckForUpdates = idleUpdater != nil
    }

    private var idleUpdater: SPUUpdater? {
        guard let updater, updater.canCheckForUpdates, !updater.sessionInProgress,
              interaction.activity == nil else { return nil }
        return updater
    }

    fileprivate func choice(for item: SUAppcastItem, state: SPUUserUpdateState) -> SPUUserUpdateChoice {
        let isNewerBuild = UpdateInteraction.isBuild(item.versionString, newerThan: AppVersion.buildNumber)
        let offer: UpdateInteraction.Offer? = if isNewerBuild, item.signingValidationStatus == .succeeded,
            !item.isInformationOnlyUpdate, item.installationType == "application", let url = item.fileURL {
            .init(version: item.displayVersionString, build: item.versionString, archiveURL: url.absoluteURL)
        } else {
            nil
        }
        if state.stage == .installing {
            return choiceForPreparedInstaller(recovering: offer)
        }
        if interaction.discovered(
            offer,
            userInitiated: state.userInitiated,
            fromSignedAppcast: signedAppcastLoaded,
            canInstallInPlace: Self.canInstallInPlace
        ) {
            return .install
        }
        // Clear a cached download so the next manual check can reach the appcast.
        if state.stage == .downloaded, state.userInitiated, !signedAppcastLoaded { return .skip }
        return .dismiss
    }

    func choiceForPreparedInstaller(recovering offer: UpdateInteraction.Offer?) -> SPUUserUpdateChoice {
        if let offer { interaction.recoverInstallerOffer(offer) }
        // Sparkle can proceed on quit if any prepared install is dismissed.
        return .skip
    }

    fileprivate func advance(to phase: UpdateInteraction.InstallPhase) {
        interaction.advance(to: phase)
    }

    fileprivate var readyChoice: SPUUserUpdateChoice {
        interaction.installAuthorized ? .install : .skip
    }

    fileprivate func finishedInstalling() {
        interaction.finishedInstalling()
    }

    // Keep the update in the user's install domain so Sparkle can work without elevation.
    private static func canInstallInPlace() -> Bool {
        let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let files = FileManager.default
        let user = geteuid()
        guard files.isWritableFile(atPath: app.path),
              files.isWritableFile(atPath: app.deletingLastPathComponent().path),
              let attributes = try? files.attributesOfItem(atPath: app.path),
              let owner = attributes[.ownerAccountID] as? NSNumber else { return false }
        return user != 0 && owner.uint32Value == user
    }
}

@MainActor
private final class InlineUpdateDriver: NSObject, SPUUserDriver {
    private weak var owner: AppUpdates?

    init(owner: AppUpdates) {
        self.owner = owner
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(
            automaticUpdateChecks: owner?.automaticallyChecksForUpdates ?? false,
            automaticUpdateDownloading: false,
            sendSystemProfile: false
        ))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    func showUpdateFound(
        with item: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        reply(owner?.choice(for: item, state: state) ?? (state.stage == .installing ? .skip : .dismiss))
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        owner?.advance(to: .downloading)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {
        owner?.advance(to: .preparing)
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(owner?.readyChoice ?? .skip)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {}

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        owner?.finishedInstalling()
        acknowledgement()
    }

    func dismissUpdateInstallation() {}
}
