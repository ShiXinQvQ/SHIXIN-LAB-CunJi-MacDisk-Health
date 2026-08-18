import Darwin
import Foundation

public actor SpeedTestRunner {
    public static let runnerVersion = "1.4"
    public static let minimumFreeSpaceBufferBytes: Int64 = 1_000_000_000

    private let store: SpeedTestStore

    public init(store: SpeedTestStore = SpeedTestStore()) {
        self.store = store
    }

    public func run(
        configuration: SpeedTestConfiguration,
        progress: (@MainActor @Sendable (SpeedTestProgress) -> Void)? = nil
    ) async throws -> SpeedTestResult {
        try Task.checkCancellation()
        let startedAt = Date()
        await emit(
            progress,
            SpeedTestProgress(
                phase: .preparing,
                testSizeBytes: configuration.testSizeBytes,
                cycleIndex: configuration.cycleIndex
            )
        )

        let targetDirectory = try SpeedTestPathPolicy.validate(directoryURL: configuration.targetDirectory)
        let beforeInfo = volumeInfo(for: targetDirectory)
        try validateFreeSpace(beforeInfo.availableBytes, requiredBytes: configuration.testSizeBytes + Self.minimumFreeSpaceBufferBytes)

        let fileURL = targetDirectory.appendingPathComponent(
            "\(SpeedTestPathPolicy.testFilePrefix)\(UUID().uuidString).bin",
            isDirectory: false
        )

        try store.recordIncomplete(
            SpeedTestIncompleteFile(
                fileURL: fileURL,
                createdAt: Date(),
                expectedSizeBytes: configuration.testSizeBytes,
                targetKind: configuration.targetKind
            )
        )

        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            try? store.removeIncomplete(fileURL: fileURL)
            throw SpeedTestFailure(
                title: "测试文件创建失败",
                message: "无法在测试目录创建临时测速文件。",
                recovery: "请选择有写入权限且空间充足的目录。"
            )
        }

        // Keep UI delivery off the storage I/O path. A busy main actor must not
        // pause file reads/writes or become part of the throughput measurement.
        let progressRelay = SpeedTestProgressRelay(callback: progress)
        do {
            try Task.checkCancellation()
            let writeMeasurement = try await writeTestFile(
                fileURL: fileURL,
                configuration: configuration,
                progressRelay: progressRelay
            )
            try Task.checkCancellation()
            let readMeasurement = try await readTestFile(
                fileURL: fileURL,
                configuration: configuration,
                progressRelay: progressRelay
            )
            try Task.checkCancellation()

            progressRelay.yield(
                SpeedTestProgress(
                    phase: .cleaningUp,
                    testSizeBytes: configuration.testSizeBytes,
                    bytesProcessed: configuration.testSizeBytes,
                    progressFraction: 1,
                    cycleIndex: configuration.cycleIndex
                )
            )
            let cleanupWarning = cleanupTestFile(fileURL)
            let afterInfo = volumeInfo(for: targetDirectory)
            var measurementWarnings = writeMeasurement.warnings + readMeasurement.warnings
            if configuration.targetConnectionKind == .networkVolume {
                measurementWarnings.append("网络文件系统测速会受到网络延迟、服务器缓存和协议缓存影响，不等同于硬盘裸性能。")
            }
            let result = SpeedTestResult(
                startedAt: startedAt,
                completedAt: Date(),
                mode: configuration.mode,
                cycleIndex: configuration.cycleIndex,
                testSizeBytes: configuration.testSizeBytes,
                writeAverageMBps: writeMeasurement.averageMBps,
                writePeakMBps: writeMeasurement.peakMBps,
                readAverageMBps: readMeasurement.averageMBps,
                readPeakMBps: readMeasurement.peakMBps,
                writeDurationSeconds: writeMeasurement.durationSeconds,
                readDurationSeconds: readMeasurement.durationSeconds,
                targetKind: configuration.targetKind,
                targetDisplayName: configuration.targetDiskDisplayName
                    ?? SpeedTestPathPolicy.displayName(for: targetDirectory, kind: configuration.targetKind),
                targetDiskIdentity: configuration.targetDiskIdentity,
                targetConnectionKind: configuration.targetConnectionKind,
                volumeName: beforeInfo.volumeName,
                volumeAvailableBeforeBytes: beforeInfo.availableBytes,
                volumeAvailableAfterBytes: afterInfo.availableBytes,
                appVersion: configuration.appVersion,
                runnerVersion: Self.runnerVersion,
                cleanupWarning: cleanupWarning,
                writeNoCacheApplied: writeMeasurement.noCacheApplied,
                readNoCacheApplied: readMeasurement.noCacheApplied,
                writeSyncSucceeded: writeMeasurement.syncSucceeded,
                measurementWarnings: measurementWarnings.isEmpty ? nil : measurementWarnings
            )
            progressRelay.yield(
                SpeedTestProgress(
                    phase: .completed,
                    testSizeBytes: configuration.testSizeBytes,
                    bytesProcessed: configuration.testSizeBytes,
                    progressFraction: 1,
                    averageMBps: result.readAverageMBps,
                    peakMBps: max(result.writePeakMBps, result.readPeakMBps),
                    elapsedSeconds: result.writeDurationSeconds + result.readDurationSeconds,
                    cycleIndex: configuration.cycleIndex
                )
            )
            await progressRelay.finish()
            return result
        } catch is CancellationError {
            progressRelay.yield(
                SpeedTestProgress(
                    phase: .cleaningUp,
                    testSizeBytes: configuration.testSizeBytes,
                    bytesProcessed: 0,
                    progressFraction: 0,
                    cycleIndex: configuration.cycleIndex
                )
            )
            _ = cleanupTestFile(fileURL)
            progressRelay.yield(
                SpeedTestProgress(
                    phase: .cancelled,
                    testSizeBytes: configuration.testSizeBytes,
                    cycleIndex: configuration.cycleIndex
                )
            )
            await progressRelay.finish()
            throw CancellationError()
        } catch let failure as SpeedTestFailure {
            _ = cleanupTestFile(fileURL)
            progressRelay.yield(
                SpeedTestProgress(
                    phase: .failed,
                    testSizeBytes: configuration.testSizeBytes,
                    cycleIndex: configuration.cycleIndex
                )
            )
            await progressRelay.finish()
            throw failure
        } catch {
            _ = cleanupTestFile(fileURL)
            progressRelay.yield(
                SpeedTestProgress(
                    phase: .failed,
                    testSizeBytes: configuration.testSizeBytes,
                    cycleIndex: configuration.cycleIndex
                )
            )
            await progressRelay.finish()
            throw SpeedTestFailure(
                title: "速度测试失败",
                message: "普通文件读写测试未能完成。",
                recovery: "请确认测试目录可写、空间充足，并关闭其他大量读写任务后重试。",
                underlyingDescription: error.localizedDescription
            )
        }
    }

    private func writeTestFile(
        fileURL: URL,
        configuration: SpeedTestConfiguration,
        progressRelay: SpeedTestProgressRelay
    ) async throws -> StageMeasurement {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        let noCacheApplied = applyNoCache(to: handle)

        // Buffer preparation is setup work, not storage throughput. Keep it outside
        // the measured interval so short tests are not distorted by CPU work.
        let buffer = makeTestBuffer(size: configuration.chunkSizeBytes)
        var sampler = StageSampler(
            phase: .writing,
            totalBytes: configuration.testSizeBytes,
            cycleIndex: configuration.cycleIndex,
            progressIntervalSeconds: configuration.progressIntervalSeconds
        )
        var written: Int64 = 0
        progressRelay.yield(sampler.progress(bytesProcessed: written, force: true))
        while written < configuration.testSizeBytes {
            try Task.checkCancellation()
            let remaining = configuration.testSizeBytes - written
            let writeCount = min(Int64(buffer.count), remaining)
            if writeCount == Int64(buffer.count) {
                try handle.write(contentsOf: buffer)
            } else {
                try handle.write(contentsOf: buffer.prefix(Int(writeCount)))
            }
            written += writeCount
            if configuration.interChunkDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: configuration.interChunkDelayNanoseconds)
            }
            if let pendingProgress = sampler.progressIfNeeded(bytesProcessed: written, force: written == configuration.testSizeBytes) {
                progressRelay.yield(pendingProgress)
            }
        }

        // Capture sequential throughput before waiting for durability
        // confirmation. fsync latency is reported separately through status and
        // must not be mislabeled as sequential SSD throughput.
        var measurement = sampler.measurement(bytesProcessed: written)
        progressRelay.yield(
            SpeedTestProgress(
                phase: .syncing,
                testSizeBytes: configuration.testSizeBytes,
                bytesProcessed: written,
                progressFraction: 1,
                currentMBps: measurement.averageMBps,
                averageMBps: measurement.averageMBps,
                peakMBps: measurement.peakMBps,
                elapsedSeconds: measurement.durationSeconds,
                cycleIndex: configuration.cycleIndex
            )
        )
        let fileHandleSyncSucceeded: Bool
        do {
            try handle.synchronize()
            fileHandleSyncSucceeded = true
        } catch {
            fileHandleSyncSucceeded = false
        }
        let descriptorSyncSucceeded = fsync(handle.fileDescriptor) == 0
        let syncSucceeded = fileHandleSyncSucceeded && descriptorSyncSucceeded
        measurement.noCacheApplied = noCacheApplied
        measurement.syncSucceeded = syncSucceeded
        if !noCacheApplied {
            measurement.warnings.append("系统未接受写入阶段的无缓存请求，结果可能受到文件系统缓存影响。")
        }
        if !syncSucceeded {
            measurement.warnings.append("底层 fsync 未确认成功，写入结果可能未完整反映持久化耗时。")
        }
        return measurement
    }

    private func readTestFile(
        fileURL: URL,
        configuration: SpeedTestConfiguration,
        progressRelay: SpeedTestProgressRelay
    ) async throws -> StageMeasurement {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let noCacheApplied = applyNoCache(to: handle)

        var sampler = StageSampler(
            phase: .reading,
            totalBytes: configuration.testSizeBytes,
            cycleIndex: configuration.cycleIndex,
            progressIntervalSeconds: configuration.progressIntervalSeconds
        )
        var readBytes: Int64 = 0
        progressRelay.yield(sampler.progress(bytesProcessed: readBytes, force: true))
        while readBytes < configuration.testSizeBytes {
            try Task.checkCancellation()
            let remaining = configuration.testSizeBytes - readBytes
            let readCount = min(Int64(configuration.chunkSizeBytes), remaining)
            guard let data = try handle.read(upToCount: Int(readCount)), !data.isEmpty else {
                throw SpeedTestFailure(
                    title: "读取测试文件失败",
                    message: "读取阶段在达到测试大小前结束。",
                    recovery: "请重新运行速度测试；如果持续失败，请换用默认临时目录。"
                )
            }
            readBytes += Int64(data.count)
            if configuration.interChunkDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: configuration.interChunkDelayNanoseconds)
            }
            if let pendingProgress = sampler.progressIfNeeded(bytesProcessed: readBytes, force: readBytes == configuration.testSizeBytes) {
                progressRelay.yield(pendingProgress)
            }
        }
        var measurement = sampler.measurement(bytesProcessed: readBytes)
        measurement.noCacheApplied = noCacheApplied
        if !noCacheApplied {
            measurement.warnings.append("系统未接受读取阶段的无缓存请求，结果可能受到文件系统缓存影响。")
        }
        return measurement
    }

    private func emit(
        _ progress: (@MainActor @Sendable (SpeedTestProgress) -> Void)?,
        _ value: SpeedTestProgress
    ) async {
        guard let progress else { return }
        await progress(value)
    }

    private func validateFreeSpace(_ availableBytes: Int64?, requiredBytes: Int64) throws {
        guard let availableBytes else {
            throw SpeedTestFailure(
                title: "无法读取可用空间",
                message: "App 无法确认测试目录所在卷的剩余容量。",
                recovery: "请选择默认临时目录或另一个普通文件夹后重试。"
            )
        }
        guard availableBytes >= requiredBytes else {
            throw SpeedTestFailure(
                title: "剩余空间不足",
                message: "速度测试需要测试大小外再预留至少 1 GB 空间。",
                recovery: "请选择更小的测试大小，或释放空间后重试。"
            )
        }
    }

    private func cleanupTestFile(_ fileURL: URL) -> String? {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                guard SpeedTestPathPolicy.canRemoveSpeedTestFile(fileURL) else {
                    throw SpeedTestFailure(
                        title: "临时文件清理被拒绝",
                        message: "目标文件不符合速度测试临时文件安全规则。",
                        recovery: "请手动检查该路径，App 不会删除非速度测试临时文件。"
                    )
                }
                try FileManager.default.removeItem(at: fileURL)
            }
            try store.removeIncomplete(fileURL: fileURL)
            return nil
        } catch {
            return SpeedTestPrivacy.genericCleanupWarning
        }
    }

    private func volumeInfo(for directory: URL) -> (availableBytes: Int64?, volumeName: String?) {
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: directory.path)
        let available = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
        let values = try? directory.resourceValues(forKeys: [.volumeNameKey])
        return (available, values?.volumeName)
    }

    private func makeTestBuffer(size: Int) -> Data {
        var data = Data(count: max(1, size))
        data.withUnsafeMutableBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for index in 0..<rawBuffer.count {
                bytes[index] = UInt8((index &* 31 &+ 17) & 0xff)
            }
        }
        return data
    }

    private func applyNoCache(to handle: FileHandle) -> Bool {
        let enabled: Int32 = 1
        return fcntl(handle.fileDescriptor, F_NOCACHE, enabled) == 0
    }
}

private struct StageMeasurement: Sendable {
    var averageMBps: Double
    var peakMBps: Double
    var durationSeconds: TimeInterval
    var noCacheApplied = false
    var syncSucceeded: Bool?
    var warnings: [String] = []
}

private struct StageSampler {
    var phase: SpeedTestPhase
    var totalBytes: Int64
    var cycleIndex: Int
    var progressIntervalSeconds: TimeInterval
    var startUptime = ProcessInfo.processInfo.systemUptime
    var lastEmitUptime = -Double.greatestFiniteMagnitude
    var lastSampleUptime = ProcessInfo.processInfo.systemUptime
    var lastSampleBytes: Int64 = 0
    var lastCurrentMBps: Double = 0
    var peakMBps: Double = 0

    mutating func progressIfNeeded(bytesProcessed: Int64, force: Bool) -> SpeedTestProgress? {
        let now = ProcessInfo.processInfo.systemUptime
        if !force, now - lastEmitUptime < progressIntervalSeconds {
            return nil
        }
        return progress(bytesProcessed: bytesProcessed, force: force)
    }

    mutating func progress(bytesProcessed: Int64, force: Bool) -> SpeedTestProgress {
        let now = ProcessInfo.processInfo.systemUptime
        let sampleElapsed = now - lastSampleUptime
        if sampleElapsed >= 0.1 || force {
            let sampleBytes = max(0, bytesProcessed - lastSampleBytes)
            if sampleElapsed >= 0.1 {
                lastCurrentMBps = Double(sampleBytes) / 1_000_000 / sampleElapsed
                peakMBps = max(peakMBps, lastCurrentMBps)
            }
            lastSampleUptime = now
            lastSampleBytes = bytesProcessed
        }

        let elapsed = max(now - startUptime, 0.000_001)
        let average = Double(bytesProcessed) / 1_000_000 / elapsed
        lastEmitUptime = now
        return SpeedTestProgress(
            phase: phase,
            testSizeBytes: totalBytes,
            bytesProcessed: bytesProcessed,
            progressFraction: totalBytes > 0 ? min(1, Double(bytesProcessed) / Double(totalBytes)) : 0,
            currentMBps: lastCurrentMBps,
            averageMBps: average,
            peakMBps: peakMBps,
            elapsedSeconds: elapsed,
            cycleIndex: cycleIndex
        )
    }

    mutating func measurement(bytesProcessed: Int64) -> StageMeasurement {
        let final = progress(bytesProcessed: bytesProcessed, force: true)
        return StageMeasurement(
            averageMBps: final.averageMBps,
            peakMBps: max(peakMBps, final.averageMBps),
            durationSeconds: max(ProcessInfo.processInfo.systemUptime - startUptime, 0.000_001)
        )
    }

}

private final class SpeedTestProgressRelay: @unchecked Sendable {
    private let continuation: AsyncStream<SpeedTestProgress>.Continuation
    private let consumerTask: Task<Void, Never>?

    init(callback: (@MainActor @Sendable (SpeedTestProgress) -> Void)?) {
        let pair = AsyncStream.makeStream(
            of: SpeedTestProgress.self,
            bufferingPolicy: .unbounded
        )
        continuation = pair.continuation
        if let callback {
            consumerTask = Task { @MainActor in
                for await value in pair.stream {
                    callback(value)
                }
            }
        } else {
            consumerTask = nil
        }
    }

    func yield(_ value: SpeedTestProgress) {
        continuation.yield(value)
    }

    func finish() async {
        continuation.finish()
        await consumerTask?.value
    }
}
