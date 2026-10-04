import Darwin
import Foundation

struct NativeWallpaperProcess: Hashable, Sendable {
    enum Role: String, Sendable {
        case agent = "WallpaperAgent"
        case aerials = "WallpaperAerialsExtension"

        var executablePath: String {
            switch self {
            case .agent:
                "/System/Library/CoreServices/WallpaperAgent.app/Contents/MacOS/WallpaperAgent"
            case .aerials:
                "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/MacOS/WallpaperAerialsExtension"
            }
        }
    }

    let role: Role
    let pid: Int32
    let uid: UInt32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    let executablePath: String
}

/// A bounded reload barrier, used only during explicit activation. It never
/// schedules wallpaper switching or leaves a helper running after app quit.
@MainActor
struct WallpaperProcessController {
    let inventory: @MainActor () throws -> Set<NativeWallpaperProcess>
    let launchdAgentPID: @MainActor () throws -> Int32
    let signal: @MainActor (NativeWallpaperProcess) throws -> Void
    let settle: @MainActor () async throws -> Void
    let maximumPolls: Int

    init(
        inventory: @escaping @MainActor () throws -> Set<NativeWallpaperProcess> = Self.nativeInventory,
        launchdAgentPID: @escaping @MainActor () throws -> Int32 = Self.nativeLaunchdAgentPID,
        signal: @escaping @MainActor (NativeWallpaperProcess) throws -> Void = Self.terminate,
        settle: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) },
        maximumPolls: Int = 80
    ) {
        self.inventory = inventory
        self.launchdAgentPID = launchdAgentPID
        self.signal = signal
        self.settle = settle
        self.maximumPolls = maximumPolls
    }

    /// Preflight trust checks before any selection write.
    func validateCurrentAgent() throws {
        _ = try trustedAgent(in: trustedInventory())
    }

    /// Snapshot after selection writing so a process restarted during that
    /// write cannot be mistaken for the verified post-write generation.
    func restartAndProveFreshAgent() async throws -> NativeWallpaperProcess {
        var previous = try trustedInventory()
        let previousAgent = try trustedAgent(in: previous)
        for actor in previous.sorted(by: { $0.role == .aerials && $1.role == .agent }) {
            try Task.checkCancellation()
            // A vanished or reused PID is not signaled. The kernel start time,
            // user and executable must still match immediately before TERM.
            if try trustedInventory().contains(actor) {
                try signal(actor)
            }
        }

        for _ in 0..<maximumPolls {
            try await settle()
            try Task.checkCancellation()
            let current = try trustedInventory()
            let agents = current.filter { $0.role == .agent }
            let candidate = agents.count == 1 ? agents.first : nil
            let fresh = candidate.flatMap { $0 == previousAgent ? nil : $0 }
            // Extensions launched by the exiting agent must also be retired.
            // Equal kernel timestamps are ambiguous and are treated as old.
            for actor in current where actor.role == .aerials
                && (fresh.map { actor.startedNoLaterThan($0) } ?? true) {
                if previous.insert(actor).inserted, try trustedInventory().contains(actor) {
                    try signal(actor)
                }
            }
            guard previous.isDisjoint(with: current), let agent = fresh else { continue }
            // Zero means launchd has not yet published the replacement PID.
            guard agent.pid == (try launchdAgentPID()) else { continue }
            return agent
        }
        throw AerialDropError.nativeWallpaperRefreshFailed("macOS did not finish restarting its wallpaper services. Try applying again.")
    }

    func verifyFreshAgent(_ agent: NativeWallpaperProcess) throws {
        let current = try trustedInventory()
        guard try trustedAgent(in: current) == agent,
              !current.contains(where: { $0.role == .aerials && $0.startedNoLaterThan(agent) }) else {
            throw AerialDropError.nativeWallpaperRefreshFailed("The wallpaper service changed during verification. Try applying again.")
        }
    }

    private func trustedInventory() throws -> Set<NativeWallpaperProcess> {
        let actors = try inventory()
        guard actors.allSatisfy({
            $0.pid > 0 && $0.uid == getuid() && $0.executablePath == $0.role.executablePath
        }) else {
            throw AerialDropError.nativeWallpaperRefreshFailed("The native wallpaper services could not be identified safely. Try again after macOS finishes changing wallpaper.")
        }
        return actors
    }

    private func trustedAgent(in actors: Set<NativeWallpaperProcess>) throws -> NativeWallpaperProcess {
        let agents = actors.filter { $0.role == .agent }
        guard agents.count == 1, let agent = agents.first, agent.pid == (try launchdAgentPID()) else {
            throw AerialDropError.nativeWallpaperRefreshFailed("The native wallpaper service is unavailable. Try applying again.")
        }
        return agent
    }

    private static func nativeInventory() throws -> Set<NativeWallpaperProcess> {
        // Allocate extra capacity for processes launched between the size and
        // inventory calls. A full buffer fails closed rather than hiding actors.
        let needed = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard needed > 0 else { throw inspectionFailure() }
        var pids = [Int32](repeating: 0, count: Int(needed) / MemoryLayout<Int32>.size + 128)
        let capacity = pids.count * MemoryLayout<Int32>.size
        let bytes = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_UID_ONLY), getuid(), $0.baseAddress, Int32($0.count))
        }
        guard bytes > 0, bytes < capacity else { throw inspectionFailure() }
        var actors = Set<NativeWallpaperProcess>()
        for pid in pids.prefix(Int(bytes) / MemoryLayout<Int32>.size) where pid > 0 {
            if let actor = try nativeActor(pid: pid) { actors.insert(actor) }
        }
        return actors
    }

    private static func nativeActor(pid: Int32) throws -> NativeWallpaperProcess? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size else {
            if errno == ESRCH { return nil }
            throw inspectionFailure()
        }
        let name = withUnsafeBytes(of: info.pbi_name) {
            String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let shortName = withUnsafeBytes(of: info.pbi_comm) {
            String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        var pathBuffer = [UInt8](repeating: 0, count: 4096)
        let pathSize = pathBuffer.withUnsafeMutableBytes {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }
        let path = String(decoding: pathBuffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        let basename = URL(fileURLWithPath: path).lastPathComponent
        let role = NativeWallpaperProcess.Role(rawValue: basename)
            ?? NativeWallpaperProcess.Role(rawValue: name)
            ?? NativeWallpaperProcess.Role.allNames.first { $0.rawValue.hasPrefix(shortName) && !shortName.isEmpty }
        guard let role else { return nil }
        guard pathSize > 0, info.pbi_uid == getuid() else { throw inspectionFailure() }
        var checked = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &checked, Int32(size)) == size,
              checked.pbi_start_tvsec == info.pbi_start_tvsec,
              checked.pbi_start_tvusec == info.pbi_start_tvusec else { throw inspectionFailure() }
        return NativeWallpaperProcess(
            role: role, pid: pid, uid: info.pbi_uid,
            startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec,
            executablePath: path
        )
    }

    private static func terminate(_ actor: NativeWallpaperProcess) throws {
        guard try nativeActor(pid: actor.pid) == actor else { return }
        guard Darwin.kill(actor.pid, SIGTERM) == 0 || errno == ESRCH else { throw inspectionFailure() }
    }

    private static func nativeLaunchdAgentPID() throws -> Int32 {
        let result = try BoundedWallpaperCommand.run(
            executableURL: URL(fileURLWithPath: "/bin/launchctl"),
            arguments: ["print", "gui/\(getuid())/com.apple.wallpaper.agent"]
        )
        guard result.status == 0 else { return 0 }
        let data = result.output
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count == 3, fields[0] == "pid", fields[1] == "=", let pid = Int32(fields[2]), pid > 0 {
                return pid
            }
        }
        return 0
    }

    private static func inspectionFailure() -> AerialDropError {
        .nativeWallpaperRefreshFailed("The native wallpaper services could not be checked. Your videos are kept; try applying again.")
    }
}

private extension NativeWallpaperProcess.Role {
    static let allNames: [Self] = [.agent, .aerials]
}

private extension NativeWallpaperProcess {
    func startedNoLaterThan(_ other: Self) -> Bool {
        startSeconds < other.startSeconds
            || (startSeconds == other.startSeconds && startMicroseconds <= other.startMicroseconds)
    }
}
