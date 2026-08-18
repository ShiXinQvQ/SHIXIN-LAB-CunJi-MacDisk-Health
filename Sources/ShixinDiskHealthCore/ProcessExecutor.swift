import Darwin
import Foundation

public enum ProcessExecutionError: Error, LocalizedError, Sendable {
    case timedOut(seconds: TimeInterval)
    case outputLimitExceeded(bytes: Int)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            "只读系统查询在 \(Int(seconds)) 秒内没有完成，已终止。"
        case .outputLimitExceeded(let bytes):
            "外部工具输出超过安全上限 \(bytes) bytes，已拒绝继续解析。"
        }
    }
}

public struct ProcessOutput: Sendable {
    public var stdout: Data
    public var stderr: Data
    public var exitStatus: Int32

    public init(stdout: Data, stderr: Data, exitStatus: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitStatus = exitStatus
    }

    public var preview: String {
        let stdoutText = String(data: stdout, encoding: .utf8) ?? ""
        let stderrText = String(data: stderr, encoding: .utf8) ?? ""
        let combined = [stdoutText, stderrText].filter { !$0.isEmpty }.joined(separator: "\n")
        return String(combined.prefix(2_000))
    }
}

public enum ProcessExecutor {
    public static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeoutSeconds: TimeInterval,
        maximumOutputBytes: Int = 16 * 1_024 * 1_024
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exitWaiter = ProcessExitWaiter()
        let controller = ProcessController(process: process)
        process.terminationHandler = { terminatedProcess in
            exitWaiter.signal(terminatedProcess.terminationStatus)
        }

        try process.run()

        return try await withTaskCancellationHandler {
            do {
                return try await withThrowingTaskGroup(of: ProcessEvent.self) { group in
                    group.addTask {
                        let capture = readAll(
                            from: stdoutPipe.fileHandleForReading,
                            maximumBytes: maximumOutputBytes
                        )
                        return .stdout(capture.data, truncated: capture.truncated)
                    }
                    group.addTask {
                        let capture = readAll(
                            from: stderrPipe.fileHandleForReading,
                            maximumBytes: maximumOutputBytes
                        )
                        return .stderr(capture.data, truncated: capture.truncated)
                    }
                    group.addTask {
                        .exit(await exitWaiter.wait())
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                        return .timeout
                    }

                    var stdout = Data()
                    var stderr = Data()
                    var exitStatus: Int32?
                    var stdoutReady = false
                    var stderrReady = false

                    while let event = try await group.next() {
                        switch event {
                        case .stdout(let data, let truncated):
                            if truncated {
                                controller.terminate()
                                throw ProcessExecutionError.outputLimitExceeded(bytes: maximumOutputBytes)
                            }
                            stdout = data
                            stdoutReady = true
                        case .stderr(let data, let truncated):
                            if truncated {
                                controller.terminate()
                                throw ProcessExecutionError.outputLimitExceeded(bytes: maximumOutputBytes)
                            }
                            stderr = data
                            stderrReady = true
                        case .exit(let status):
                            exitStatus = status
                        case .timeout:
                            controller.terminate()
                            throw ProcessExecutionError.timedOut(seconds: timeoutSeconds)
                        }

                        if stdoutReady, stderrReady, let exitStatus {
                            group.cancelAll()
                            return ProcessOutput(stdout: stdout, stderr: stderr, exitStatus: exitStatus)
                        }
                    }

                    throw CancellationError()
                }
            } catch {
                controller.terminate()
                throw error
            }
        } onCancel: {
            controller.terminate()
        }
    }

    private static func readAll(from handle: FileHandle, maximumBytes: Int) -> (data: Data, truncated: Bool) {
        var result = Data()
        while true {
            do {
                guard let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty else { break }
                let remaining = maximumBytes - result.count
                guard remaining > 0 else {
                    return (result, true)
                }
                result.append(chunk.prefix(remaining))
                if chunk.count > remaining {
                    return (result, true)
                }
            } catch {
                break
            }
        }
        return (result, false)
    }
}

private enum ProcessEvent: Sendable {
    case stdout(Data, truncated: Bool)
    case stderr(Data, truncated: Bool)
    case exit(Int32)
    case timeout
}

private final class ProcessExitWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    func signal(_ status: Int32) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: status)
        } else {
            self.status = status
            lock.unlock()
        }
    }

    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}

private final class ProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var didRequestTermination = false

    init(process: Process) {
        self.process = process
    }

    func terminate() {
        lock.lock()
        guard !didRequestTermination else {
            lock.unlock()
            return
        }
        didRequestTermination = true
        let pid = process.processIdentifier
        let running = process.isRunning
        lock.unlock()

        guard running else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stillRunning = self.process.isRunning
            self.lock.unlock()
            if stillRunning {
                _ = Darwin.kill(pid, SIGKILL)
            }
        }
    }
}
