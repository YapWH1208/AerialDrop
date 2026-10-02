import Darwin
import Foundation

/// Runs a short native inspection command without waiting indefinitely for a
/// child or a pipe. Only the child created here can be terminated on timeout.
enum BoundedWallpaperCommand {
    struct Result {
        let output: Data
        let status: Int32
    }

    static func run(executableURL: URL, arguments: [String], timeout: Duration = .seconds(2)) throws -> Result {
        let task = Process()
        let pipe = Pipe()
        let fd = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else { throw failure() }
        task.executableURL = executableURL
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var observedExit = false
        while true {
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                if count > 0 {
                    output.append(contentsOf: buffer.prefix(count))
                    guard output.count <= 65_536 else {
                        stop(task)
                        throw failure()
                    }
                } else {
                    guard count == 0 || errno == EAGAIN || errno == EINTR else {
                        stop(task)
                        throw failure()
                    }
                    break
                }
            }
            if !task.isRunning {
                // Drain once more after observing exit: the child may have
                // written its final bytes after the preceding nonblocking read.
                if observedExit { return Result(output: output, status: task.terminationStatus) }
                observedExit = true
                continue
            }
            guard ContinuousClock.now < deadline else {
                stop(task)
                throw failure()
            }
            usleep(5_000)
        }
    }

    private static func stop(_ task: Process) {
        if task.isRunning { task.terminate() }
        if task.isRunning { _ = Darwin.kill(task.processIdentifier, SIGKILL) }
    }

    private static func failure() -> AerialDropError {
        .nativeWallpaperRefreshFailed("The native wallpaper service lookup did not finish. Your videos are kept; try applying again.")
    }
}
