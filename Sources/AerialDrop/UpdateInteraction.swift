import Foundation
import Sparkle

struct UpdateInteraction {
    struct Offer: Equatable {
        let version: String
        let build: String
        let archiveURL: URL
    }

    enum InstallPhase: Equatable {
        case downloading, preparing, waitingForWork, relaunching
    }

    enum Activity: Equatable {
        case checking
        case verifying(Offer)
        case installing(InstallPhase)

        var description: LocalizedStringResource {
            switch self {
            case .checking: "Checking for updates…"
            case .verifying: "Checking the update…"
            case .installing(.downloading): "Downloading update…"
            case .installing(.preparing): "Preparing update…"
            case .installing(.waitingForWork): "Waiting for current work to finish…"
            case .installing(.relaunching): "Installing update and relaunching…"
            }
        }
    }

    enum Feedback: Equatable {
        case noCompatibleUpdate, checkFailed, installFailed, needsWritableLocation

        var description: LocalizedStringResource {
            switch self {
            case .noCompatibleUpdate: "No compatible update is available."
            case .checkFailed: "Couldn’t check for updates. Try again."
            case .installFailed: "Couldn’t install the update. Try again."
            case .needsWritableLocation: "Update AerialDrop manually or move it to an Applications folder you can write to."
            }
        }
    }

    private(set) var offer: Offer?
    private(set) var recoveredOffer: Offer?
    private(set) var activity: Activity?
    private(set) var feedback: Feedback?

    init(recoveredOffer: Offer? = nil) {
        self.offer = recoveredOffer
        self.recoveredOffer = recoveredOffer
    }

    static func isBuild(_ build: String, newerThan otherBuild: String) -> Bool {
        SUStandardVersionComparator.default.compareVersion(build, toVersion: otherBuild) == .orderedDescending
    }

    var installAuthorized: Bool {
        if case .installing = activity { true } else { false }
    }

    mutating func beginCheck() {
        activity = .checking
        feedback = nil
    }

    mutating func beginInstall(canInstallInPlace: Bool) -> Bool {
        guard activity == nil, let offer else { return false }
        guard canInstallInPlace else {
            feedback = .needsWritableLocation
            return false
        }
        activity = .verifying(offer)
        feedback = nil
        return true
    }

    mutating func recoverInstallerOffer(_ candidate: Offer) {
        if let offer, Self.isBuild(offer.build, newerThan: candidate.build) { return }
        recoveredOffer = candidate
        offer = candidate
    }

    mutating func discovered(
        _ candidate: Offer?,
        userInitiated: Bool,
        fromSignedAppcast: Bool,
        canInstallInPlace: () -> Bool
    ) -> Bool {
        if let recoveredOffer, candidate != recoveredOffer {
            // Background checks can omit a build after Sparkle cancels and skips it.
            let supersedesRecovery = candidate.map { Self.isBuild($0.build, newerThan: recoveredOffer.build) } ?? false
            guard fromSignedAppcast, userInitiated || supersedesRecovery else {
                if userInitiated { reportFailure() }
                return false
            }
            self.recoveredOffer = nil
        }
        offer = candidate
        guard let candidate else {
            if activity != nil { feedback = .noCompatibleUpdate }
            return false
        }

        feedback = nil
        guard userInitiated, activity == .verifying(candidate) else { return false }
        guard fromSignedAppcast else {
            reportFailure()
            return false
        }
        guard canInstallInPlace() else {
            feedback = .needsWritableLocation
            return false
        }

        activity = .installing(.preparing)
        return true
    }

    mutating func advance(to phase: InstallPhase) {
        guard installAuthorized else { return }
        activity = .installing(phase)
    }

    mutating func reportedMissingUpdate(userInitiated: Bool, fromSignedAppcast: Bool) {
        if recoveredOffer != nil {
            guard userInitiated, fromSignedAppcast else {
                if userInitiated { reportFailure() }
                return
            }
            recoveredOffer = nil
        }
        offer = nil
        feedback = activity == nil ? nil : .noCompatibleUpdate
    }

    mutating func finish(failed: Bool = false) {
        if failed { reportFailure() }
        activity = nil
    }

    mutating func finishedInstalling() {
        offer = nil
        recoveredOffer = nil
        finish()
    }

    private mutating func reportFailure() {
        if let activity {
            feedback = activity == .checking ? .checkFailed : .installFailed
        }
    }
}
