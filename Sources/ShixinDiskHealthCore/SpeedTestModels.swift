import Foundation

public enum SpeedTestSizeOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case oneGB = "1 GB"
    case fiveGB = "5 GB"
    case tenGB = "10 GB"
    case fiftyGB = "50 GB"

    public var id: String { rawValue }
    public static let defaultOption: Self = .fiveGB

    public var bytes: Int64 {
        switch self {
        case .oneGB: 1_000_000_000
        case .fiveGB: 5_000_000_000
        case .tenGB: 10_000_000_000
        case .fiftyGB: 50_000_000_000
        }
    }

    public var title: String { rawValue }
}

public enum SpeedTestMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case single = "单次"
    case continuous = "连续"

    public var id: String { rawValue }
}

public enum SpeedTestTargetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case defaultCacheDirectory = "默认临时目录"
    case userSelectedDirectory = "用户选择目录"

    public var id: String { rawValue }
}

public enum SpeedTestPhase: String, Codable, CaseIterable, Identifiable, Sendable {
    case idle = "待测试"
    case preparing = "准备中"
    case writing = "写入中"
    case syncing = "同步中"
    case reading = "读取中"
    case cleaningUp = "清理中"
    case completed = "已完成"
    case cancelled = "已停止"
    case failed = "失败"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .idle: "speedometer"
        case .preparing: "hourglass"
        case .writing: "square.and.arrow.down.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .reading: "square.and.arrow.up.fill"
        case .cleaningUp: "trash"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "stop.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

public enum SpeedTestPrivacy {
    public static let genericCleanupWarning = "临时测速文件未能自动清理；App 已保留安全清理记录，并会在下次启动时重试。"
}

public struct SpeedTestConfiguration: Codable, Hashable, Sendable {
    public var testSizeBytes: Int64
    public var displaySizeLabel: String
    public var mode: SpeedTestMode
    public var targetDirectory: URL
    public var targetKind: SpeedTestTargetKind
    public var targetDiskIdentity: DiskIdentityKey?
    public var targetConnectionKind: DiskConnectionKind?
    public var targetDiskDisplayName: String?
    public var cycleIndex: Int
    public var appVersion: String
    public var chunkSizeBytes: Int
    public var progressIntervalSeconds: TimeInterval
    public var interChunkDelayNanoseconds: UInt64

    public init(
        sizeOption: SpeedTestSizeOption,
        mode: SpeedTestMode,
        targetDirectory: URL,
        targetKind: SpeedTestTargetKind,
        targetDiskIdentity: DiskIdentityKey? = nil,
        targetConnectionKind: DiskConnectionKind? = nil,
        targetDiskDisplayName: String? = nil,
        cycleIndex: Int,
        appVersion: String,
        chunkSizeBytes: Int = 16 * 1_024 * 1_024,
        progressIntervalSeconds: TimeInterval = 0.25,
        interChunkDelayNanoseconds: UInt64 = 0
    ) {
        self.testSizeBytes = sizeOption.bytes
        self.displaySizeLabel = sizeOption.title
        self.mode = mode
        self.targetDirectory = targetDirectory
        self.targetKind = targetKind
        self.targetDiskIdentity = targetDiskIdentity
        self.targetConnectionKind = targetConnectionKind
        self.targetDiskDisplayName = targetDiskDisplayName
        self.cycleIndex = cycleIndex
        self.appVersion = appVersion
        self.chunkSizeBytes = chunkSizeBytes
        self.progressIntervalSeconds = progressIntervalSeconds
        self.interChunkDelayNanoseconds = interChunkDelayNanoseconds
    }

    public init(
        testSizeBytes: Int64,
        displaySizeLabel: String,
        mode: SpeedTestMode,
        targetDirectory: URL,
        targetKind: SpeedTestTargetKind,
        targetDiskIdentity: DiskIdentityKey? = nil,
        targetConnectionKind: DiskConnectionKind? = nil,
        targetDiskDisplayName: String? = nil,
        cycleIndex: Int,
        appVersion: String,
        chunkSizeBytes: Int = 16 * 1_024 * 1_024,
        progressIntervalSeconds: TimeInterval = 0.25,
        interChunkDelayNanoseconds: UInt64 = 0
    ) {
        self.testSizeBytes = testSizeBytes
        self.displaySizeLabel = displaySizeLabel
        self.mode = mode
        self.targetDirectory = targetDirectory
        self.targetKind = targetKind
        self.targetDiskIdentity = targetDiskIdentity
        self.targetConnectionKind = targetConnectionKind
        self.targetDiskDisplayName = targetDiskDisplayName
        self.cycleIndex = cycleIndex
        self.appVersion = appVersion
        self.chunkSizeBytes = chunkSizeBytes
        self.progressIntervalSeconds = progressIntervalSeconds
        self.interChunkDelayNanoseconds = interChunkDelayNanoseconds
    }
}

public struct SpeedTestProgress: Codable, Hashable, Sendable {
    public var phase: SpeedTestPhase
    public var testSizeBytes: Int64
    public var bytesProcessed: Int64
    public var progressFraction: Double
    public var currentMBps: Double
    public var averageMBps: Double
    public var peakMBps: Double
    public var elapsedSeconds: TimeInterval
    public var cycleIndex: Int

    public init(
        phase: SpeedTestPhase = .idle,
        testSizeBytes: Int64 = 0,
        bytesProcessed: Int64 = 0,
        progressFraction: Double = 0,
        currentMBps: Double = 0,
        averageMBps: Double = 0,
        peakMBps: Double = 0,
        elapsedSeconds: TimeInterval = 0,
        cycleIndex: Int = 1
    ) {
        self.phase = phase
        self.testSizeBytes = testSizeBytes
        self.bytesProcessed = bytesProcessed
        self.progressFraction = progressFraction
        self.currentMBps = currentMBps
        self.averageMBps = averageMBps
        self.peakMBps = peakMBps
        self.elapsedSeconds = elapsedSeconds
        self.cycleIndex = cycleIndex
    }
}

public struct SpeedTestResult: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var completedAt: Date
    public var mode: SpeedTestMode
    public var cycleIndex: Int
    public var testSizeBytes: Int64
    public var writeAverageMBps: Double
    public var writePeakMBps: Double
    public var readAverageMBps: Double
    public var readPeakMBps: Double
    public var writeDurationSeconds: TimeInterval
    public var readDurationSeconds: TimeInterval
    public var targetKind: SpeedTestTargetKind
    public var targetDisplayName: String
    public var targetDiskIdentity: DiskIdentityKey?
    public var targetConnectionKind: DiskConnectionKind?
    public var volumeName: String?
    public var volumeAvailableBeforeBytes: Int64?
    public var volumeAvailableAfterBytes: Int64?
    public var appVersion: String
    public var runnerVersion: String
    public var cleanupWarning: String?
    public var writeNoCacheApplied: Bool?
    public var readNoCacheApplied: Bool?
    public var writeSyncSucceeded: Bool?
    public var measurementWarnings: [String]?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        completedAt: Date,
        mode: SpeedTestMode,
        cycleIndex: Int,
        testSizeBytes: Int64,
        writeAverageMBps: Double,
        writePeakMBps: Double,
        readAverageMBps: Double,
        readPeakMBps: Double,
        writeDurationSeconds: TimeInterval,
        readDurationSeconds: TimeInterval,
        targetKind: SpeedTestTargetKind,
        targetDisplayName: String,
        targetDiskIdentity: DiskIdentityKey? = nil,
        targetConnectionKind: DiskConnectionKind? = nil,
        volumeName: String?,
        volumeAvailableBeforeBytes: Int64?,
        volumeAvailableAfterBytes: Int64?,
        appVersion: String,
        runnerVersion: String,
        cleanupWarning: String? = nil,
        writeNoCacheApplied: Bool? = nil,
        readNoCacheApplied: Bool? = nil,
        writeSyncSucceeded: Bool? = nil,
        measurementWarnings: [String]? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.mode = mode
        self.cycleIndex = cycleIndex
        self.testSizeBytes = testSizeBytes
        self.writeAverageMBps = writeAverageMBps
        self.writePeakMBps = writePeakMBps
        self.readAverageMBps = readAverageMBps
        self.readPeakMBps = readPeakMBps
        self.writeDurationSeconds = writeDurationSeconds
        self.readDurationSeconds = readDurationSeconds
        self.targetKind = targetKind
        self.targetDisplayName = targetDisplayName
        self.targetDiskIdentity = targetDiskIdentity
        self.targetConnectionKind = targetConnectionKind
        self.volumeName = volumeName
        self.volumeAvailableBeforeBytes = volumeAvailableBeforeBytes
        self.volumeAvailableAfterBytes = volumeAvailableAfterBytes
        self.appVersion = appVersion
        self.runnerVersion = runnerVersion
        self.cleanupWarning = cleanupWarning
        self.writeNoCacheApplied = writeNoCacheApplied
        self.readNoCacheApplied = readNoCacheApplied
        self.writeSyncSucceeded = writeSyncSucceeded
        self.measurementWarnings = measurementWarnings
    }

    public var historyGroupKey: String {
        Self.makeHistoryGroupKey(
            targetDiskIdentity: targetDiskIdentity,
            targetConnectionKind: targetConnectionKind,
            targetKind: targetKind,
            targetDisplayName: targetDisplayName,
            volumeName: volumeName
        )
    }

    public static func makeHistoryGroupKey(
        targetDiskIdentity: DiskIdentityKey?,
        targetConnectionKind: DiskConnectionKind?,
        targetKind: SpeedTestTargetKind,
        targetDisplayName: String,
        volumeName: String?
    ) -> String {
        if let identity = targetDiskIdentity?.rawValue {
            return "disk:\(identity)"
        }
        return [
            "target",
            targetConnectionKind?.rawValue ?? targetKind.rawValue,
            targetDisplayName,
            volumeName ?? ""
        ].joined(separator: ":")
    }
}

public struct SpeedTestFailure: Error, Codable, Hashable, Sendable, LocalizedError {
    public var title: String
    public var message: String
    public var recovery: String
    public var underlyingDescription: String?

    public init(
        title: String,
        message: String,
        recovery: String,
        underlyingDescription: String? = nil
    ) {
        self.title = title
        self.message = message
        self.recovery = recovery
        self.underlyingDescription = underlyingDescription
    }

    public var errorDescription: String? {
        "\(title)：\(message)"
    }
}

public struct SpeedTestIncompleteFile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var fileURL: URL
    public var createdAt: Date
    public var expectedSizeBytes: Int64
    public var targetKind: SpeedTestTargetKind

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        createdAt: Date,
        expectedSizeBytes: Int64,
        targetKind: SpeedTestTargetKind
    ) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.expectedSizeBytes = expectedSizeBytes
        self.targetKind = targetKind
    }
}

public enum SpeedTestPathPolicy {
    public static let testFilePrefix = ".shixinlab-speedtest-"

    public static func validate(directoryURL: URL) throws -> URL {
        guard directoryURL.isFileURL else {
            throw SpeedTestFailure(
                title: "测试目录无效",
                message: "只能选择本机文件系统中的普通文件夹。",
                recovery: "请选择一个普通文件夹，或使用默认临时目录。"
            )
        }

        let resolvedURL = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let path = resolvedURL.path
        guard path != "/" else {
            throw SpeedTestFailure(
                title: "不能使用磁盘根目录",
                message: "速度测试不会直接在磁盘根目录创建测试文件。",
                recovery: "请选择用户文件夹或使用默认临时目录。"
            )
        }
        guard !isDevicePath(path) else {
            throw SpeedTestFailure(
                title: "禁止使用原始磁盘设备路径",
                message: "速度测试不能写入 /dev 或任何原始磁盘设备。",
                recovery: "请选择普通文件夹。"
            )
        }
        guard !isInsideAppBundle(resolvedURL) else {
            throw SpeedTestFailure(
                title: "不能使用 App 包内目录",
                message: "测试文件不能写入应用程序包内部。",
                recovery: "请选择普通用户目录或使用默认临时目录。"
            )
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SpeedTestFailure(
                title: "测试目录不存在",
                message: "选择的路径不是可用文件夹。",
                recovery: "请选择一个已经存在的文件夹。"
            )
        }
        guard FileManager.default.isWritableFile(atPath: path) else {
            throw SpeedTestFailure(
                title: "测试目录不可写",
                message: "当前 App 无法在这个目录创建普通测试文件。",
                recovery: "请选择有写入权限的文件夹，或使用默认临时目录。"
            )
        }

        return resolvedURL
    }

    public static func canRemoveSpeedTestFile(_ fileURL: URL) -> Bool {
        let resolvedURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
        let escapedPrefix = NSRegularExpression.escapedPattern(for: testFilePrefix)
        let uuidPattern = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        let fileNamePattern = "^\(escapedPrefix)\(uuidPattern)\\.bin$"
        guard resolvedURL.lastPathComponent.range(of: fileNamePattern, options: .regularExpression) != nil else { return false }
        guard !isDevicePath(resolvedURL.path) else { return false }
        guard let values = try? resolvedURL.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else {
            return false
        }
        return true
    }

    public static func displayName(for directoryURL: URL, kind: SpeedTestTargetKind) -> String {
        switch kind {
        case .defaultCacheDirectory:
            "默认临时目录"
        case .userSelectedDirectory:
            directoryURL.lastPathComponent.isEmpty ? "用户选择目录" : directoryURL.lastPathComponent
        }
    }

    private static func isDevicePath(_ path: String) -> Bool {
        path == "/dev" || path.hasPrefix("/dev/")
    }

    private static func isInsideAppBundle(_ url: URL) -> Bool {
        if let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let path = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           path.hasPrefix(bundleURL) {
            return true
        }

        return url.pathComponents.contains { component in
            component.hasSuffix(".app")
        }
    }
}
