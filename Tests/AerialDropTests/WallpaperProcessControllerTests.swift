import Darwin
import Foundation
import XCTest
@testable import AerialDrop

@MainActor
final class WallpaperProcessControllerTests: XCTestCase {
    func testPreflightRequiresExactlyOneTrustedLaunchdAgent() throws {
        let agent = actor(.agent, pid: 101)
        let extensionActor = actor(.aerials, pid: 102)
        let harness = ProcessHarness(current: [agent], launchdPID: agent.pid)
        try harness.controller().validateCurrentAgent()
        harness.current = [agent, extensionActor]
        try harness.controller().validateCurrentAgent()
        XCTAssertTrue(harness.signals.isEmpty)
        XCTAssertEqual(harness.polls, 0)

        for inventory: Set<NativeWallpaperProcess> in [[], [extensionActor], [agent, actor(.agent, pid: 103)]] {
            harness.current = inventory
            XCTAssertThrowsError(try harness.controller().validateCurrentAgent())
        }
        harness.current = [agent]
        harness.launchdPID = 999
        XCTAssertThrowsError(try harness.controller().validateCurrentAgent())
        XCTAssertTrue(harness.signals.isEmpty)
    }

    func testPreflightRejectsForeignUIDUntrustedPathAndInvalidPID() throws {
        let agent = actor(.agent, pid: 101)
        let harness = ProcessHarness(current: [agent], launchdPID: agent.pid)
        let invalidActors = [
            actor(.agent, pid: 101, uid: getuid() &+ 1),
            actor(.agent, pid: 101, path: "/tmp/WallpaperAgent"),
            actor(.agent, pid: 0),
            actor(.aerials, pid: 102, uid: getuid() &+ 1),
            actor(.aerials, pid: 102, path: "/tmp/WallpaperAerialsExtension")
        ]
        for invalid in invalidActors {
            harness.current = invalid.role == .agent ? [invalid] : [agent, invalid]
            XCTAssertThrowsError(try harness.controller().validateCurrentAgent())
        }
        XCTAssertTrue(harness.signals.isEmpty)
    }

    func testRestartAcceptsNoExtensionAndProvesFreshLaunchdAgent() async throws {
        let old = actor(.agent, pid: 101)
        let fresh = actor(.agent, pid: 201, start: 2)
        let harness = ProcessHarness(current: [old], launchdPID: old.pid)
        harness.onSignal = { actor in
            harness.current.remove(actor)
            harness.current.insert(fresh)
            harness.launchdPID = fresh.pid
        }
        let controller = harness.controller()
        let proof = try await controller.restartAndProveFreshAgent()
        XCTAssertEqual(proof, fresh)
        XCTAssertEqual(harness.signals, [old])
        try controller.verifyFreshAgent(proof)
    }

    func testSignalsEveryExtensionBeforeAgent() async throws {
        let old = actor(.agent, pid: 101)
        let first = actor(.aerials, pid: 102)
        let second = actor(.aerials, pid: 103)
        let fresh = actor(.agent, pid: 201, start: 2)
        let harness = ProcessHarness(current: [old, first, second], launchdPID: old.pid)
        harness.onSignal = { actor in
            harness.current.remove(actor)
            if actor.role == .agent {
                harness.current.insert(fresh)
                harness.launchdPID = fresh.pid
            }
        }
        let proof = try await harness.controller().restartAndProveFreshAgent()
        XCTAssertEqual(proof, fresh)
        XCTAssertEqual(harness.signals.count, 3)
        XCTAssertEqual(Set(harness.signals.prefix(2)), [first, second])
        XCTAssertEqual(harness.signals.last, old)
    }

    func testReusedExtensionPIDIsNeverSignaledAsItsOldIdentity() async throws {
        let old = actor(.agent, pid: 101)
        let extensionActor = actor(.aerials, pid: 102)
        let reused = actor(.aerials, pid: 102, start: 1, microseconds: 2)
        let fresh = actor(.agent, pid: 201, start: 2)
        let harness = ProcessHarness(current: [old, extensionActor], launchdPID: old.pid)
        harness.onInventory = {
            if harness.inventoryCalls == 2 {
                harness.current.remove(extensionActor)
                harness.current.insert(reused)
            }
        }
        harness.onSignal = { actor in
            harness.current.remove(actor)
            harness.current.insert(fresh)
            harness.launchdPID = fresh.pid
        }
        let proof = try await harness.controller().restartAndProveFreshAgent()
        XCTAssertEqual(proof, fresh)
        XCTAssertFalse(harness.signals.contains(extensionActor))
        XCTAssertEqual(Set(harness.signals), [old, reused])
        XCTAssertFalse(harness.current.contains(reused))
    }

    func testReusedAgentPIDWithNewStartTimeIsFreshAndNotSignaled() async throws {
        let old = actor(.agent, pid: 101)
        let fresh = actor(.agent, pid: 101, start: 2)
        let harness = ProcessHarness(current: [old], launchdPID: old.pid)
        harness.onInventory = {
            if harness.inventoryCalls == 2 { harness.current = [fresh] }
        }
        let proof = try await harness.controller().restartAndProveFreshAgent()
        XCTAssertEqual(proof, fresh)
        XCTAssertTrue(harness.signals.isEmpty)
    }

    func testEveryOldExtensionMustExitBeforeFreshProof() async throws {
        let old = actor(.agent, pid: 101)
        let extensionActor = actor(.aerials, pid: 102)
        let fresh = actor(.agent, pid: 201, start: 2)
        let harness = ProcessHarness(current: [old, extensionActor], launchdPID: old.pid)
        harness.onSignal = { actor in
            if actor.role == .agent {
                harness.current.remove(old)
                harness.current.insert(fresh)
                harness.launchdPID = fresh.pid
            }
        }
        harness.onSettle = {
            if harness.polls == 2 { harness.current.remove(extensionActor) }
        }
        let proof = try await harness.controller().restartAndProveFreshAgent()
        XCTAssertEqual(proof, fresh)
        XCTAssertEqual(harness.polls, 2)
    }

    func testLingeringOldExtensionOrOldAgentTimesOut() async throws {
        let old = actor(.agent, pid: 101)
        let extensionActor = actor(.aerials, pid: 102)
        let fresh = actor(.agent, pid: 201, start: 2)
        for keepsAgent in [false, true] {
            let harness = ProcessHarness(current: [old, extensionActor], launchdPID: old.pid)
            harness.onSettle = {
                harness.current = keepsAgent ? [old] : [fresh, extensionActor]
                harness.launchdPID = keepsAgent ? old.pid : fresh.pid
            }
            do {
                _ = try await harness.controller(maximumPolls: 2).restartAndProveFreshAgent()
                XCTFail("An old native process must prevent a fresh proof")
            } catch {
                assertRefreshFailure(error)
            }
            XCTAssertEqual(harness.polls, 2)
        }
    }

    func testFreshAgentMustMatchLaunchdAfterRestart() async throws {
        let old = actor(.agent, pid: 101)
        let fresh = actor(.agent, pid: 201, start: 2)
        let harness = ProcessHarness(current: [old], launchdPID: old.pid)
        harness.onSettle = {
            harness.current = [fresh]
            harness.launchdPID = harness.polls == 1 ? 999 : fresh.pid
        }
        let proof = try await harness.controller().restartAndProveFreshAgent()
        XCTAssertEqual(proof, fresh)
        XCTAssertEqual(harness.polls, 2)
    }

    func testCancellationBeforeSignalAndDuringSettlePropagates() async throws {
        let old = actor(.agent, pid: 101)
        let before = ProcessHarness(current: [old], launchdPID: old.pid)
        let task = Task { try await before.controller().restartAndProveFreshAgent() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(before.signals.isEmpty)

        let during = ProcessHarness(current: [old], launchdPID: old.pid)
        during.onSettle = { throw CancellationError() }
        do {
            _ = try await during.controller().restartAndProveFreshAgent()
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(during.signals, [old])
    }

    func testInspectionAndSignalFailuresPropagateWithoutContinuing() async throws {
        let old = actor(.agent, pid: 101)
        let harness = ProcessHarness(current: [old], launchdPID: old.pid)
        harness.onInventory = { throw ProcessTestError.inspection }
        XCTAssertThrowsError(try harness.controller().validateCurrentAgent()) { error in
            XCTAssertEqual(error as? ProcessTestError, .inspection)
        }
        do {
            _ = try await harness.controller().restartAndProveFreshAgent()
            XCTFail("Expected inspection failure")
        } catch { XCTAssertEqual(error as? ProcessTestError, .inspection) }
        XCTAssertTrue(harness.signals.isEmpty)
        harness.onInventory = nil
        harness.onSignal = { _ in throw ProcessTestError.signal }
        do {
            _ = try await harness.controller().restartAndProveFreshAgent()
            XCTFail("Expected signal failure")
        } catch { XCTAssertEqual(error as? ProcessTestError, .signal) }
        XCTAssertEqual(harness.polls, 0)
    }

    func testFreshProofRejectsAgentIdentityOrLaunchdChanges() throws {
        let fresh = actor(.agent, pid: 201, start: 2)
        let harness = ProcessHarness(current: [fresh], launchdPID: fresh.pid)
        let controller = harness.controller()
        try controller.verifyFreshAgent(fresh)
        harness.current = [actor(.agent, pid: fresh.pid, start: 3)]
        XCTAssertThrowsError(try controller.verifyFreshAgent(fresh))
        harness.current = [fresh]
        harness.launchdPID = 999
        XCTAssertThrowsError(try controller.verifyFreshAgent(fresh))
        XCTAssertTrue(harness.signals.isEmpty)
    }

    func testInspectionFailureDuringPollingAndFinalVerificationNeverProvesSuccess() async throws {
        let old = actor(.agent, pid: 101)
        let fresh = actor(.agent, pid: 201, start: 2)
        let harness = ProcessHarness(current: [old], launchdPID: old.pid)
        harness.onSignal = { _ in
            harness.current = [fresh]
            harness.launchdPID = fresh.pid
        }
        harness.onInventory = {
            if harness.inventoryCalls == 3 { throw ProcessTestError.inspection }
        }
        do {
            _ = try await harness.controller().restartAndProveFreshAgent()
            XCTFail("A failed polling inspection cannot prove a fresh agent")
        } catch { XCTAssertEqual(error as? ProcessTestError, .inspection) }
        XCTAssertEqual(harness.polls, 1)
        harness.onInventory = { throw ProcessTestError.inspection }
        XCTAssertThrowsError(try harness.controller().verifyFreshAgent(fresh)) { error in
            XCTAssertEqual(error as? ProcessTestError, .inspection)
        }
        harness.onInventory = nil
        harness.onLaunchd = { throw ProcessTestError.inspection }
        XCTAssertThrowsError(try harness.controller().validateCurrentAgent()) { error in
            XCTAssertEqual(error as? ProcessTestError, .inspection)
        }
    }

    func testLateExtensionSpawnedBeforeFreshAgentIsRetiredAndWaitedFor() async throws {
        let old = actor(.agent, pid: 101, start: 1)
        let late = actor(.aerials, pid: 102, start: 2)
        let fresh = actor(.agent, pid: 201, start: 3)
        let harness = ProcessHarness(current: [old], launchdPID: old.pid)
        harness.onSignal = { process in
            if process == old {
                harness.current = []
                harness.launchdPID = 0
            }
            // The late extension deliberately remains alive after TERM.
        }
        harness.onSettle = {
            switch harness.polls {
            case 1:
                harness.current = [late]
            case 2:
                harness.current.insert(fresh)
                harness.launchdPID = fresh.pid
            default:
                harness.current.remove(late)
            }
        }
        let proof = try await harness.controller(maximumPolls: 5).restartAndProveFreshAgent()
        XCTAssertEqual(proof, fresh)
        XCTAssertEqual(Set(harness.signals), [old, late])
        XCTAssertGreaterThanOrEqual(harness.polls, 3)
        XCTAssertFalse(harness.current.contains(late))
    }

    func testFreshProofRejectsOlderAndEqualExtensionGenerationsButAllowsNewer() throws {
        let fresh = actor(.agent, pid: 201, start: 3, microseconds: 5)
        let harness = ProcessHarness(current: [fresh], launchdPID: fresh.pid)
        let controller = harness.controller()
        for extensionActor in [
            actor(.aerials, pid: 102, start: 2, microseconds: 99),
            actor(.aerials, pid: 102, start: 3, microseconds: 4),
            actor(.aerials, pid: 102, start: 3, microseconds: 5)
        ] {
            harness.current = [fresh, extensionActor]
            XCTAssertThrowsError(try controller.verifyFreshAgent(fresh))
        }
        for extensionActor in [
            actor(.aerials, pid: 102, start: 3, microseconds: 6),
            actor(.aerials, pid: 102, start: 4, microseconds: 1)
        ] {
            harness.current = [fresh, extensionActor]
            try controller.verifyFreshAgent(fresh)
        }
        XCTAssertTrue(harness.signals.isEmpty)
    }

    func testRepeatedFreshProofRejectsExtensionAppearingBetweenVerificationReads() throws {
        let fresh = actor(.agent, pid: 201, start: 3, microseconds: 5)
        let late = actor(.aerials, pid: 102, start: 3, microseconds: 4)
        let harness = ProcessHarness(current: [fresh], launchdPID: fresh.pid)
        harness.onInventory = {
            if harness.inventoryCalls == 2 { harness.current.insert(late) }
        }
        // The service brackets catalogue/selection verification with this
        // proof. A later extension must invalidate the second proof.
        try harness.controller().verifyFreshAgent(fresh)
        XCTAssertThrowsError(try harness.controller().verifyFreshAgent(fresh))
        XCTAssertTrue(harness.signals.isEmpty)
    }

    func testRestartAllowsExtensionNewerThanFreshAgent() async throws {
        let old = actor(.agent, pid: 101, start: 1)
        let fresh = actor(.agent, pid: 201, start: 3, microseconds: 5)
        let newer = actor(.aerials, pid: 102, start: 3, microseconds: 6)
        let harness = ProcessHarness(current: [old], launchdPID: old.pid)
        harness.onSignal = { _ in harness.current.remove(old) }
        harness.onSettle = {
            harness.current = [fresh, newer]
            harness.launchdPID = fresh.pid
        }
        let proof = try await harness.controller().restartAndProveFreshAgent()
        XCTAssertEqual(proof, fresh)
        XCTAssertEqual(harness.signals, [old])
        XCTAssertTrue(harness.current.contains(newer))
    }

    private func actor(
        _ role: NativeWallpaperProcess.Role, pid: Int32,
        start: UInt64 = 1, microseconds: UInt64 = 1,
        uid: UInt32 = getuid(), path: String? = nil
    ) -> NativeWallpaperProcess {
        NativeWallpaperProcess(
            role: role, pid: pid, uid: uid,
            startSeconds: start, startMicroseconds: microseconds,
            executablePath: path ?? role.executablePath
        )
    }

    private func assertRefreshFailure(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        guard case AerialDropError.nativeWallpaperRefreshFailed = error else {
            return XCTFail("Expected nativeWallpaperRefreshFailed, got \(error)", file: file, line: line)
        }
    }
}

@MainActor
private final class ProcessHarness {
    var current: Set<NativeWallpaperProcess>
    var launchdPID: Int32
    var signals: [NativeWallpaperProcess] = []
    var polls = 0
    var inventoryCalls = 0
    var onInventory: (() throws -> Void)?
    var onLaunchd: (() throws -> Void)?
    var onSignal: ((NativeWallpaperProcess) throws -> Void)?
    var onSettle: (() throws -> Void)?

    init(current: Set<NativeWallpaperProcess>, launchdPID: Int32) {
        self.current = current
        self.launchdPID = launchdPID
    }

    func controller(maximumPolls: Int = 3) -> WallpaperProcessController {
        WallpaperProcessController(
            inventory: {
                self.inventoryCalls += 1
                try self.onInventory?()
                return self.current
            },
            launchdAgentPID: {
                try self.onLaunchd?()
                return self.launchdPID
            },
            signal: { actor in
                self.signals.append(actor)
                try self.onSignal?(actor)
            },
            settle: {
                self.polls += 1
                try self.onSettle?()
            },
            maximumPolls: maximumPolls
        )
    }
}

private enum ProcessTestError: Error, Equatable {
    case inspection
    case signal
}
