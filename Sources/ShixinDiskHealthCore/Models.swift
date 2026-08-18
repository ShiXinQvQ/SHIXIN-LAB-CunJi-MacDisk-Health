import Foundation

public enum HealthLevel: Hashable, Sendable, CaseIterable, Codable {
    case healthy
    case attention
    case risk
    case unknown

    public var symbolName: String {
        switch self {
        case .healthy: "checkmark.seal.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .risk: "xmark.octagon.fill"
        case .unknown: "questionmark.diamond.fill"
        }
    }

    public var title: String {
        switch self {
        case .healthy: "健康"
        case .attention: "需要关注"
        case .risk: "风险"
        case .unknown: "无法判断"
        }
    }

    public var shortDescription: String {
        switch self {
        case .healthy: "当前未发现关键风险"
        case .attention: "存在需要关注的信号"
        case .risk: "建议尽快备份并进一步检查"
        case .unknown: "核心健康数据不足"
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "健康": self = .healthy
        case "注意", "需要关注": self = .attention
        case "风险": self = .risk
        case "无法判断": self = .unknown
        default: self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(title)
    }
}

public enum ReadCompleteness: String, Codable, Sendable, CaseIterable {
    case complete = "完整读取"
    case coreCompleteSupplementalUnavailable = "核心数据已读取，附加日志不可用"
    case coreMissing = "核心字段缺失"
    case failed = "读取失败"

    public var symbolName: String {
        switch self {
        case .complete: "checkmark.circle.fill"
        case .coreCompleteSupplementalUnavailable: "info.circle.fill"
        case .coreMissing: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    public var shortDescription: String {
        switch self {
        case .complete:
            "核心健康数据和扩展信息均已读取。"
        case .coreCompleteSupplementalUnavailable:
            "核心 SMART 健康数据已读取成功；附加错误日志明细不可用，不等同于硬盘故障。"
        case .coreMissing:
            "设备信息存在，但核心健康字段不足，无法形成可靠健康结论。"
        case .failed:
            "smartctl 未能返回可用的健康报告。"
        }
    }
}

public enum ReadMode: String, Codable, Sendable, CaseIterable {
    case bundled = "App 内置 smartctl"
    case homebrewAppleSilicon = "/opt/homebrew/bin/smartctl"
    case homebrewIntel = "/usr/local/bin/smartctl"
    case path = "PATH 中的 smartctl"
    case manual = "手动选择 smartctl"
    case privilegedHelper = "Privileged Helper"
    case unknown = "未知来源"
}

public enum DiskConnectionKind: String, Codable, Sendable, CaseIterable {
    case internalPhysical = "内置本地硬盘"
    case externalPhysical = "外置本地硬盘"
    case networkVolume = "网络卷"
    case unknown = "未知"

    public var shortTitle: String {
        switch self {
        case .internalPhysical: "内置"
        case .externalPhysical: "外置"
        case .networkVolume: "网络"
        case .unknown: "未知"
        }
    }

    public var symbolName: String {
        switch self {
        case .internalPhysical: "internaldrive"
        case .externalPhysical: "externaldrive"
        case .networkVolume: "network"
        case .unknown: "questionmark.folder"
        }
    }
}

public enum SmartSupportStatus: String, Codable, Sendable, CaseIterable {
    case supported = "可尝试读取 SMART"
    case unsupportedNetworkVolume = "网络卷不支持 SMART"
    case unsupportedNoWholeDisk = "缺少 whole-disk 设备节点"
    case unsupportedVirtualDisk = "虚拟磁盘可能不支持 SMART"
    case unknown = "待检测"

    public var canReadSMART: Bool {
        self == .supported || self == .unknown
    }
}

public enum SmartctlDeviceType: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto = "auto"
    case nvme = "nvme"
    case sat = "sat"
    case scsi = "scsi"
    case sntASMedia = "sntasmedia"
    case sntJMicron = "sntjmicron"
    case sntRealtek = "sntrealtek"

    public var id: String { rawValue }

    public var argumentPrefix: [String] {
        switch self {
        case .auto:
            []
        case .nvme, .sat, .scsi, .sntASMedia, .sntJMicron, .sntRealtek:
            ["-d", rawValue]
        }
    }

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .nvme: "NVMe"
        case .sat: "SAT"
        case .scsi: "SCSI"
        case .sntASMedia: "SNT ASMedia"
        case .sntJMicron: "SNT JMicron"
        case .sntRealtek: "SNT Realtek"
        }
    }
}

public enum DiskProtocolFamily: String, Codable, Hashable, Sendable, CaseIterable {
    case nvme = "NVMe"
    case ata = "ATA / SATA"
    case scsi = "SCSI / SAS"
    case unknown = "SMART"

    public static func infer(
        deviceType: String?,
        protocolName: String?,
        hasNVMeLog: Bool = false,
        hasATAAttributes: Bool = false,
        hasSCSIErrorCounters: Bool = false
    ) -> DiskProtocolFamily {
        if hasNVMeLog { return .nvme }
        if hasATAAttributes { return .ata }
        if hasSCSIErrorCounters { return .scsi }

        let text = [deviceType, protocolName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if text.contains("nvme") { return .nvme }
        if text.contains("ata") || text.contains("sat") { return .ata }
        if text.contains("scsi") || text.contains("sas") { return .scsi }
        return .unknown
    }
}

public struct DiskIdentityKey: Codable, Hashable, Sendable {
    public var rawValue: String
    public var source: String

    public init(rawValue: String, source: String) {
        self.rawValue = rawValue
        self.source = source
    }

    public var isStrong: Bool {
        switch source {
        case "smartctl-serial", "disk-arbitration-media-uuid", "disk-arbitration-related-media-uuid":
            true
        default:
            false
        }
    }

    public static func smartctlSerial(_ value: String?) -> DiskIdentityKey? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        let invalidValues = ["unknown", "n/a", "na", "none", "null", "not available", "to be filled by o.e.m.", "-"]
        let compact = normalized.filter { $0.isLetter || $0.isNumber }
        guard !invalidValues.contains(normalized), compact.count >= 4, Set(compact).count > 1 else {
            return nil
        }
        return DiskIdentityKey(rawValue: "serial:\(trimmed)", source: "smartctl-serial")
    }
}

public struct SmartctlAccessProfile: Codable, Hashable, Sendable {
    public var devicePath: String
    public var allowedDeviceTypes: [SmartctlDeviceType]

    public init(devicePath: String, allowedDeviceTypes: [SmartctlDeviceType] = [.auto]) {
        self.devicePath = devicePath
        self.allowedDeviceTypes = SmartctlAccessProfile.normalizedDeviceTypes(allowedDeviceTypes)
    }

    private static func normalizedDeviceTypes(_ values: [SmartctlDeviceType]) -> [SmartctlDeviceType] {
        var seen: Set<SmartctlDeviceType> = []
        var result: [SmartctlDeviceType] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result.isEmpty ? [.auto] : result
    }
}

public struct DiskTarget: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var detailName: String?
    public var connectionKind: DiskConnectionKind
    public var smartSupportStatus: SmartSupportStatus
    public var smartctlAccessProfile: SmartctlAccessProfile?
    public var identityKey: DiskIdentityKey?
    public var volumeURL: URL?
    public var volumeName: String?
    public var isLocalVolume: Bool
    public var isInternal: Bool?
    public var protocolName: String?
    public var modelName: String?
    public var mediaSizeBytes: Int64?
    public var volumeCapacityBytes: Int64?
    public var volumeAvailableBytes: Int64?

    public init(
        id: String,
        displayName: String,
        detailName: String? = nil,
        connectionKind: DiskConnectionKind,
        smartSupportStatus: SmartSupportStatus,
        smartctlAccessProfile: SmartctlAccessProfile? = nil,
        identityKey: DiskIdentityKey? = nil,
        volumeURL: URL? = nil,
        volumeName: String? = nil,
        isLocalVolume: Bool = true,
        isInternal: Bool? = nil,
        protocolName: String? = nil,
        modelName: String? = nil,
        mediaSizeBytes: Int64? = nil,
        volumeCapacityBytes: Int64? = nil,
        volumeAvailableBytes: Int64? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.detailName = detailName
        self.connectionKind = connectionKind
        self.smartSupportStatus = smartSupportStatus
        self.smartctlAccessProfile = smartctlAccessProfile
        self.identityKey = identityKey
        self.volumeURL = volumeURL
        self.volumeName = volumeName
        self.isLocalVolume = isLocalVolume
        self.isInternal = isInternal
        self.protocolName = protocolName
        self.modelName = modelName
        self.mediaSizeBytes = mediaSizeBytes
        self.volumeCapacityBytes = volumeCapacityBytes
        self.volumeAvailableBytes = volumeAvailableBytes
    }

    public var canReadSMART: Bool {
        smartctlAccessProfile != nil && smartSupportStatus.canReadSMART
    }

    public var devicePath: String? {
        smartctlAccessProfile?.devicePath
    }
}

public struct DiskInventory: Codable, Hashable, Sendable {
    public var targets: [DiskTarget]
    public var capturedAt: Date

    public init(targets: [DiskTarget] = [], capturedAt: Date = Date()) {
        self.targets = targets
        self.capturedAt = capturedAt
    }

    public var smartTargets: [DiskTarget] {
        targets.filter(\.canReadSMART)
    }

    public var speedTestTargets: [DiskTarget] {
        targets.filter { $0.volumeURL != nil }
    }

    public var preferredTargetID: DiskTarget.ID? {
        smartTargets.first(where: { $0.smartctlAccessProfile?.devicePath == "/dev/disk0" })?.id
            ?? smartTargets.first(where: { $0.connectionKind == .internalPhysical })?.id
            ?? smartTargets.first?.id
    }

    public func smartTarget(matching previousTarget: DiskTarget) -> DiskTarget? {
        if let previousIdentity = previousTarget.identityKey, previousIdentity.isStrong {
            let identityMatches = smartTargets.filter { candidate in
                guard let candidateIdentity = candidate.identityKey, candidateIdentity.isStrong else {
                    return false
                }
                return candidateIdentity.rawValue == previousIdentity.rawValue
            }
            if identityMatches.count == 1 {
                return identityMatches[0]
            }
            if let previousDevicePath = previousTarget.devicePath {
                let sameNodeMatches = identityMatches.filter { $0.devicePath == previousDevicePath }
                if sameNodeMatches.count == 1 {
                    return sameNodeMatches[0]
                }
            }
            return nil
        }

        guard let previousDevicePath = previousTarget.devicePath else { return nil }
        let matches = smartTargets.filter { candidate in
            guard candidate.devicePath == previousDevicePath,
                  candidate.connectionKind == previousTarget.connectionKind else {
                return false
            }
            if let previousModel = previousTarget.modelName,
               let candidateModel = candidate.modelName,
               previousModel.caseInsensitiveCompare(candidateModel) != .orderedSame {
                return false
            }
            if let previousSize = previousTarget.mediaSizeBytes,
               let candidateSize = candidate.mediaSizeBytes,
               previousSize != candidateSize {
                return false
            }
            if let previousProtocol = previousTarget.protocolName,
               let candidateProtocol = candidate.protocolName,
               previousProtocol.caseInsensitiveCompare(candidateProtocol) != .orderedSame {
                return false
            }
            return true
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

public struct SmartctlMessage: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var severity: String
    public var message: String

    public init(id: UUID = UUID(), severity: String, message: String) {
        self.id = id
        self.severity = severity
        self.message = message
    }
}

public struct SmartctlDiagnostic: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var arguments: [String]
    public var exitStatus: Int32?
    public var messages: [SmartctlMessage]
    public var stderrText: String?

    public init(
        id: UUID = UUID(),
        title: String,
        arguments: [String],
        exitStatus: Int32?,
        messages: [SmartctlMessage],
        stderrText: String?
    ) {
        self.id = id
        self.title = title
        self.arguments = arguments
        self.exitStatus = exitStatus
        self.messages = messages
        self.stderrText = stderrText
    }
}

public struct SmartDeviceInfo: Codable, Hashable, Sendable {
    public var deviceName: String
    public var infoName: String?
    public var type: String?
    public var protocolName: String?
    public var modelName: String?
    public var serialNumber: String?
    public var firmwareVersion: String?
    public var nvmeVersion: String?
    public var namespaceCount: Int?
    public var rotationRateRPM: Int?
    public var ataVersion: String?
    public var sataVersion: String?
    public var scsiVersion: String?

    public init(
        deviceName: String,
        infoName: String? = nil,
        type: String? = nil,
        protocolName: String? = nil,
        modelName: String? = nil,
        serialNumber: String? = nil,
        firmwareVersion: String? = nil,
        nvmeVersion: String? = nil,
        namespaceCount: Int? = nil,
        rotationRateRPM: Int? = nil,
        ataVersion: String? = nil,
        sataVersion: String? = nil,
        scsiVersion: String? = nil
    ) {
        self.deviceName = deviceName
        self.infoName = infoName
        self.type = type
        self.protocolName = protocolName
        self.modelName = modelName
        self.serialNumber = serialNumber
        self.firmwareVersion = firmwareVersion
        self.nvmeVersion = nvmeVersion
        self.namespaceCount = namespaceCount
        self.rotationRateRPM = rotationRateRPM
        self.ataVersion = ataVersion
        self.sataVersion = sataVersion
        self.scsiVersion = scsiVersion
    }
}

public struct ATASmartAttribute: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var currentValue: Int?
    public var worstValue: Int?
    public var threshold: Int?
    public var whenFailed: String?
    public var rawValue: Int64?
    public var rawString: String?

    public init(
        id: Int,
        name: String,
        currentValue: Int? = nil,
        worstValue: Int? = nil,
        threshold: Int? = nil,
        whenFailed: String? = nil,
        rawValue: Int64? = nil,
        rawString: String? = nil
    ) {
        self.id = id
        self.name = name
        self.currentValue = currentValue
        self.worstValue = worstValue
        self.threshold = threshold
        self.whenFailed = whenFailed
        self.rawValue = rawValue
        self.rawString = rawString
    }

    public var isFailingNow: Bool {
        let failure = whenFailed?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") ?? ""
        if failure == "now" || failure.contains("failing_now") || failure.contains("failed_now") {
            return true
        }
        if failure == "past" || failure.contains("past") { return false }
        guard let currentValue, let threshold, threshold > 0 else { return false }
        return currentValue <= threshold
    }

    public var hasFailedInPast: Bool {
        whenFailed?.lowercased().contains("past") == true
    }

    public var hasFailed: Bool { isFailingNow }
}

public struct SCSIErrorCounter: Codable, Hashable, Sendable {
    public var correctedFast: Int64?
    public var correctedDelayed: Int64?
    public var rereadsOrRewrites: Int64?
    public var totalCorrected: Int64?
    public var correctionAlgorithmInvocations: Int64?
    public var gigabytesProcessed: Double?
    public var totalUncorrected: Int64?

    public init(
        correctedFast: Int64? = nil,
        correctedDelayed: Int64? = nil,
        rereadsOrRewrites: Int64? = nil,
        totalCorrected: Int64? = nil,
        correctionAlgorithmInvocations: Int64? = nil,
        gigabytesProcessed: Double? = nil,
        totalUncorrected: Int64? = nil
    ) {
        self.correctedFast = correctedFast
        self.correctedDelayed = correctedDelayed
        self.rereadsOrRewrites = rereadsOrRewrites
        self.totalCorrected = totalCorrected
        self.correctionAlgorithmInvocations = correctionAlgorithmInvocations
        self.gigabytesProcessed = gigabytesProcessed
        self.totalUncorrected = totalUncorrected
    }

    public var hasData: Bool {
        correctedFast != nil || correctedDelayed != nil || rereadsOrRewrites != nil ||
            totalCorrected != nil || correctionAlgorithmInvocations != nil ||
            gigabytesProcessed != nil || totalUncorrected != nil
    }
}

public struct SCSIErrorCounters: Codable, Hashable, Sendable {
    public var read: SCSIErrorCounter?
    public var write: SCSIErrorCounter?
    public var verify: SCSIErrorCounter?

    public init(read: SCSIErrorCounter? = nil, write: SCSIErrorCounter? = nil, verify: SCSIErrorCounter? = nil) {
        self.read = read
        self.write = write
        self.verify = verify
    }

    public var hasData: Bool {
        read?.hasData == true || write?.hasData == true || verify?.hasData == true
    }
}

public struct SmartHealthMetrics: Codable, Hashable, Sendable {
    public var protocolFamily: DiskProtocolFamily?
    public var smartPassed: Bool?
    public var criticalWarning: Int?
    public var temperatureCelsius: Int?
    public var availableSparePercent: Int?
    public var availableSpareThresholdPercent: Int?
    public var percentageUsed: Int?
    public var dataUnitsRead: Int64?
    public var dataUnitsWritten: Int64?
    public var hostReads: Int64?
    public var hostWrites: Int64?
    public var controllerBusyTime: Int64?
    public var powerCycles: Int64?
    public var powerOnHours: Int64?
    public var unsafeShutdowns: Int64?
    public var mediaErrors: Int64?
    public var errorLogEntries: Int64?
    public var reallocatedSectorCount: Int64?
    public var reallocationEventCount: Int64?
    public var currentPendingSectorCount: Int64?
    public var offlineUncorrectableSectorCount: Int64?
    public var reportedUncorrectableErrors: Int64?
    public var commandTimeoutCount: Int64?
    public var crcErrorCount: Int64?
    public var endToEndErrorCount: Int64?
    public var ataAttributeCount: Int?
    public var ataFailingAttributeCount: Int?
    public var ataPastFailureAttributeCount: Int?
    public var scsiGrownDefectList: Int64?
    public var scsiNonMediumErrorCount: Int64?
    public var scsiReadUncorrectedErrors: Int64?
    public var scsiWriteUncorrectedErrors: Int64?
    public var scsiVerifyUncorrectedErrors: Int64?
    public var scsiErrorCounterAvailable: Bool?

    public init(
        protocolFamily: DiskProtocolFamily? = nil,
        smartPassed: Bool? = nil,
        criticalWarning: Int? = nil,
        temperatureCelsius: Int? = nil,
        availableSparePercent: Int? = nil,
        availableSpareThresholdPercent: Int? = nil,
        percentageUsed: Int? = nil,
        dataUnitsRead: Int64? = nil,
        dataUnitsWritten: Int64? = nil,
        hostReads: Int64? = nil,
        hostWrites: Int64? = nil,
        controllerBusyTime: Int64? = nil,
        powerCycles: Int64? = nil,
        powerOnHours: Int64? = nil,
        unsafeShutdowns: Int64? = nil,
        mediaErrors: Int64? = nil,
        errorLogEntries: Int64? = nil,
        reallocatedSectorCount: Int64? = nil,
        reallocationEventCount: Int64? = nil,
        currentPendingSectorCount: Int64? = nil,
        offlineUncorrectableSectorCount: Int64? = nil,
        reportedUncorrectableErrors: Int64? = nil,
        commandTimeoutCount: Int64? = nil,
        crcErrorCount: Int64? = nil,
        endToEndErrorCount: Int64? = nil,
        ataAttributeCount: Int? = nil,
        ataFailingAttributeCount: Int? = nil,
        ataPastFailureAttributeCount: Int? = nil,
        scsiGrownDefectList: Int64? = nil,
        scsiNonMediumErrorCount: Int64? = nil,
        scsiReadUncorrectedErrors: Int64? = nil,
        scsiWriteUncorrectedErrors: Int64? = nil,
        scsiVerifyUncorrectedErrors: Int64? = nil,
        scsiErrorCounterAvailable: Bool? = nil
    ) {
        self.protocolFamily = protocolFamily
        self.smartPassed = smartPassed
        self.criticalWarning = criticalWarning
        self.temperatureCelsius = temperatureCelsius
        self.availableSparePercent = availableSparePercent
        self.availableSpareThresholdPercent = availableSpareThresholdPercent
        self.percentageUsed = percentageUsed
        self.dataUnitsRead = dataUnitsRead
        self.dataUnitsWritten = dataUnitsWritten
        self.hostReads = hostReads
        self.hostWrites = hostWrites
        self.controllerBusyTime = controllerBusyTime
        self.powerCycles = powerCycles
        self.powerOnHours = powerOnHours
        self.unsafeShutdowns = unsafeShutdowns
        self.mediaErrors = mediaErrors
        self.errorLogEntries = errorLogEntries
        self.reallocatedSectorCount = reallocatedSectorCount
        self.reallocationEventCount = reallocationEventCount
        self.currentPendingSectorCount = currentPendingSectorCount
        self.offlineUncorrectableSectorCount = offlineUncorrectableSectorCount
        self.reportedUncorrectableErrors = reportedUncorrectableErrors
        self.commandTimeoutCount = commandTimeoutCount
        self.crcErrorCount = crcErrorCount
        self.endToEndErrorCount = endToEndErrorCount
        self.ataAttributeCount = ataAttributeCount
        self.ataFailingAttributeCount = ataFailingAttributeCount
        self.ataPastFailureAttributeCount = ataPastFailureAttributeCount
        self.scsiGrownDefectList = scsiGrownDefectList
        self.scsiNonMediumErrorCount = scsiNonMediumErrorCount
        self.scsiReadUncorrectedErrors = scsiReadUncorrectedErrors
        self.scsiWriteUncorrectedErrors = scsiWriteUncorrectedErrors
        self.scsiVerifyUncorrectedErrors = scsiVerifyUncorrectedErrors
        self.scsiErrorCounterAvailable = scsiErrorCounterAvailable
    }

    public var readBytes: Double? {
        dataUnitsRead.map { Double($0) * 512_000 }
    }

    public var writtenBytes: Double? {
        dataUnitsWritten.map { Double($0) * 512_000 }
    }

    public var hasCoreFields: Bool {
        smartPassed != nil ||
            criticalWarning != nil ||
            temperatureCelsius != nil ||
            percentageUsed != nil ||
            dataUnitsRead != nil ||
            dataUnitsWritten != nil ||
            (ataAttributeCount ?? 0) > 0 ||
            scsiErrorCounterAvailable == true ||
            scsiGrownDefectList != nil
    }

    public var effectiveProtocolFamily: DiskProtocolFamily {
        if let protocolFamily { return protocolFamily }
        if criticalWarning != nil || availableSparePercent != nil || dataUnitsRead != nil { return .nvme }
        if (ataAttributeCount ?? 0) > 0 { return .ata }
        if scsiErrorCounterAvailable == true || scsiGrownDefectList != nil { return .scsi }
        return .unknown
    }

    public var hasRequiredHealthFields: Bool {
        switch effectiveProtocolFamily {
        case .nvme:
            return smartPassed != nil &&
                criticalWarning != nil &&
                temperatureCelsius != nil &&
                availableSparePercent != nil &&
                availableSpareThresholdPercent != nil &&
                percentageUsed != nil &&
                mediaErrors != nil &&
                errorLogEntries != nil
        case .ata:
            let hasSafetyEvidence = reallocatedSectorCount != nil ||
                currentPendingSectorCount != nil ||
                offlineUncorrectableSectorCount != nil ||
                reportedUncorrectableErrors != nil ||
                endToEndErrorCount != nil ||
                ataFailingAttributeCount != nil
            return smartPassed != nil && (ataAttributeCount ?? 0) > 0 && hasSafetyEvidence
        case .scsi:
            return smartPassed != nil &&
                (scsiErrorCounterAvailable == true || scsiGrownDefectList != nil || scsiNonMediumErrorCount != nil)
        case .unknown:
            return false
        }
    }
}

public struct SmartSnapshot: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var capturedAt: Date
    public var device: SmartDeviceInfo
    public var metrics: SmartHealthMetrics
    public var healthLevel: HealthLevel
    public var healthReasons: [String]
    public var readMode: ReadMode
    public var smartctlPath: String?
    public var smartctlVersion: String?
    public var smartctlExitStatus: Int32?
    public var smartctlMessages: [SmartctlMessage]
    public var rawJSON: String
    public var readCompleteness: ReadCompleteness?
    public var readCompletenessReasons: [String]?
    public var smartctlDiagnostics: [SmartctlDiagnostic]?
    public var coreRawJSON: String?
    public var extendedRawJSON: String?
    public var diskIdentity: DiskIdentityKey?
    public var diskDisplayName: String?
    public var diskConnectionKind: DiskConnectionKind?
    public var diskDevicePath: String?
    public var ataAttributes: [ATASmartAttribute]?
    public var scsiErrorCounters: SCSIErrorCounters?

    public init(
        id: UUID = UUID(),
        capturedAt: Date,
        device: SmartDeviceInfo,
        metrics: SmartHealthMetrics,
        healthLevel: HealthLevel,
        healthReasons: [String],
        readMode: ReadMode,
        smartctlPath: String?,
        smartctlVersion: String?,
        smartctlExitStatus: Int32?,
        smartctlMessages: [SmartctlMessage],
        rawJSON: String,
        readCompleteness: ReadCompleteness? = nil,
        readCompletenessReasons: [String]? = nil,
        smartctlDiagnostics: [SmartctlDiagnostic]? = nil,
        coreRawJSON: String? = nil,
        extendedRawJSON: String? = nil,
        diskIdentity: DiskIdentityKey? = nil,
        diskDisplayName: String? = nil,
        diskConnectionKind: DiskConnectionKind? = nil,
        diskDevicePath: String? = nil,
        ataAttributes: [ATASmartAttribute]? = nil,
        scsiErrorCounters: SCSIErrorCounters? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.device = device
        self.metrics = metrics
        self.healthLevel = healthLevel
        self.healthReasons = healthReasons
        self.readMode = readMode
        self.smartctlPath = smartctlPath
        self.smartctlVersion = smartctlVersion
        self.smartctlExitStatus = smartctlExitStatus
        self.smartctlMessages = smartctlMessages
        self.rawJSON = rawJSON
        self.readCompleteness = readCompleteness
        self.readCompletenessReasons = readCompletenessReasons
        self.smartctlDiagnostics = smartctlDiagnostics
        self.coreRawJSON = coreRawJSON
        self.extendedRawJSON = extendedRawJSON
        self.diskIdentity = diskIdentity
        self.diskDisplayName = diskDisplayName
        self.diskConnectionKind = diskConnectionKind
        self.diskDevicePath = diskDevicePath
        self.ataAttributes = ataAttributes
        self.scsiErrorCounters = scsiErrorCounters
    }

    public var displayReadCompleteness: ReadCompleteness {
        readCompleteness ?? HealthEvaluator.readCompleteness(
            metrics: metrics,
            messages: smartctlMessages,
            exitStatus: smartctlExitStatus
        ).level
    }

    public var displayReadCompletenessReasons: [String] {
        readCompletenessReasons ?? HealthEvaluator.readCompleteness(
            metrics: metrics,
            messages: smartctlMessages,
            exitStatus: smartctlExitStatus
        ).reasons
    }

    public func reevaluatedForDisplay() -> SmartSnapshot {
        var copy = self
        let completeness = HealthEvaluator.readCompleteness(
            metrics: metrics,
            messages: smartctlMessages,
            exitStatus: smartctlExitStatus
        )
        let evaluation = HealthEvaluator.evaluate(
            metrics: metrics,
            readCompleteness: completeness.level,
            smartctlExitStatus: smartctlExitStatus
        )
        copy.healthLevel = evaluation.level
        copy.healthReasons = evaluation.reasons
        copy.readCompleteness = readCompleteness ?? completeness.level
        copy.readCompletenessReasons = readCompletenessReasons ?? completeness.reasons
        return copy
    }

    public var effectiveDiskIdentity: DiskIdentityKey {
        if let serialIdentity = DiskIdentityKey.smartctlSerial(device.serialNumber) {
            return serialIdentity
        }
        if let diskIdentity {
            return diskIdentity
        }
        return DiskIdentityKey(rawValue: "device:\(device.deviceName)", source: "legacy-device")
    }

    public func belongs(to target: DiskTarget) -> Bool {
        if let snapshotIdentity = diskIdentity,
           snapshotIdentity.isStrong,
           let targetIdentity = target.identityKey,
           targetIdentity.isStrong {
            return snapshotIdentity.rawValue == targetIdentity.rawValue
        }
        if let devicePath = target.devicePath {
            if diskDevicePath == devicePath || device.deviceName == devicePath {
                return true
            }
        }
        if let targetIdentity = target.identityKey,
           targetIdentity.isStrong,
           diskIdentity?.rawValue == targetIdentity.rawValue {
            return true
        }
        return false
    }

    public mutating func applyDiskTarget(_ target: DiskTarget) {
        diskIdentity = target.identityKey
        diskDisplayName = target.displayName
        diskConnectionKind = target.connectionKind
        diskDevicePath = target.devicePath
        if let devicePath = target.devicePath {
            device.deviceName = devicePath
        }
    }
}

public struct SnapshotDelta: Codable, Hashable, Sendable {
    public var protocolFamily: DiskProtocolFamily
    public var readBytes: Double?
    public var writtenBytes: Double?
    public var powerOnHours: Int64?
    public var powerCycles: Int64?
    public var unsafeShutdowns: Int64?
    public var mediaErrors: Int64?
    public var errorLogEntries: Int64?
    public var percentageUsed: Int?
    public var reallocatedSectorCount: Int64?
    public var currentPendingSectorCount: Int64?
    public var offlineUncorrectableSectorCount: Int64?
    public var crcErrorCount: Int64?
    public var scsiReadUncorrectedErrors: Int64?
    public var scsiWriteUncorrectedErrors: Int64?
    public var scsiVerifyUncorrectedErrors: Int64?

    public init(current: SmartSnapshot, previous: SmartSnapshot) {
        self.protocolFamily = current.metrics.effectiveProtocolFamily
        self.readBytes = SnapshotDelta.diff(current.metrics.readBytes, previous.metrics.readBytes)
        self.writtenBytes = SnapshotDelta.diff(current.metrics.writtenBytes, previous.metrics.writtenBytes)
        self.powerOnHours = SnapshotDelta.diff(current.metrics.powerOnHours, previous.metrics.powerOnHours)
        self.powerCycles = SnapshotDelta.diff(current.metrics.powerCycles, previous.metrics.powerCycles)
        self.unsafeShutdowns = SnapshotDelta.diff(current.metrics.unsafeShutdowns, previous.metrics.unsafeShutdowns)
        self.mediaErrors = SnapshotDelta.diff(current.metrics.mediaErrors, previous.metrics.mediaErrors)
        self.errorLogEntries = SnapshotDelta.diff(current.metrics.errorLogEntries, previous.metrics.errorLogEntries)
        self.percentageUsed = SnapshotDelta.diff(current.metrics.percentageUsed, previous.metrics.percentageUsed)
        self.reallocatedSectorCount = SnapshotDelta.diff(current.metrics.reallocatedSectorCount, previous.metrics.reallocatedSectorCount)
        self.currentPendingSectorCount = SnapshotDelta.diff(current.metrics.currentPendingSectorCount, previous.metrics.currentPendingSectorCount)
        self.offlineUncorrectableSectorCount = SnapshotDelta.diff(current.metrics.offlineUncorrectableSectorCount, previous.metrics.offlineUncorrectableSectorCount)
        self.crcErrorCount = SnapshotDelta.diff(current.metrics.crcErrorCount, previous.metrics.crcErrorCount)
        self.scsiReadUncorrectedErrors = SnapshotDelta.diff(current.metrics.scsiReadUncorrectedErrors, previous.metrics.scsiReadUncorrectedErrors)
        self.scsiWriteUncorrectedErrors = SnapshotDelta.diff(current.metrics.scsiWriteUncorrectedErrors, previous.metrics.scsiWriteUncorrectedErrors)
        self.scsiVerifyUncorrectedErrors = SnapshotDelta.diff(current.metrics.scsiVerifyUncorrectedErrors, previous.metrics.scsiVerifyUncorrectedErrors)
    }

    private static func diff<T: BinaryInteger>(_ lhs: T?, _ rhs: T?) -> T? {
        guard let lhs, let rhs else { return nil }
        return lhs - rhs
    }

    private static func diff(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else { return nil }
        return lhs - rhs
    }
}

public struct SmartctlLocation: Codable, Hashable, Sendable {
    public var executableURL: URL
    public var mode: ReadMode
    public var label: String

    public init(executableURL: URL, mode: ReadMode, label: String) {
        self.executableURL = executableURL
        self.mode = mode
        self.label = label
    }
}

public struct SmartctlFailure: Error, Codable, Hashable, Sendable {
    public var title: String
    public var message: String
    public var recovery: String
    public var exitStatus: Int32?
    public var checkedPaths: [String]
    public var rawOutputPreview: String?

    public init(
        title: String,
        message: String,
        recovery: String,
        exitStatus: Int32? = nil,
        checkedPaths: [String] = [],
        rawOutputPreview: String? = nil
    ) {
        self.title = title
        self.message = message
        self.recovery = recovery
        self.exitStatus = exitStatus
        self.checkedPaths = checkedPaths
        self.rawOutputPreview = rawOutputPreview
    }
}

public enum SmartctlReadOutcome: Sendable {
    case success(SmartSnapshot)
    case failure(SmartctlFailure)
}
