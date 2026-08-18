import Foundation

public struct HealthEvaluation: Codable, Hashable, Sendable {
    public var level: HealthLevel
    public var reasons: [String]

    public init(level: HealthLevel, reasons: [String]) {
        self.level = level
        self.reasons = reasons
    }
}

public struct ReadCompletenessEvaluation: Codable, Hashable, Sendable {
    public var level: ReadCompleteness
    public var reasons: [String]

    public init(level: ReadCompleteness, reasons: [String]) {
        self.level = level
        self.reasons = reasons
    }
}

public enum HealthEvaluator {
    public static func evaluate(
        metrics: SmartHealthMetrics,
        readCompleteness: ReadCompleteness,
        smartctlExitStatus: Int32? = nil
    ) -> HealthEvaluation {
        guard metrics.hasRequiredHealthFields else {
            return HealthEvaluation(
                level: .unknown,
                reasons: ["该协议形成健康结论所需的核心 SMART 字段不完整，无法可靠判断。"]
            )
        }

        var level = HealthLevel.healthy
        var reasons: [String] = []

        func raise(_ newLevel: HealthLevel, _ reason: String) {
            if newLevel == .risk || (newLevel == .attention && level == .healthy) || level == .unknown {
                level = newLevel
            }
            reasons.append(reason)
        }

        if metrics.smartPassed == false {
            raise(.risk, "SMART 整体状态未通过。")
        }
        switch metrics.effectiveProtocolFamily {
        case .nvme:
            if let warning = metrics.criticalWarning, warning != 0 {
                raise(.risk, "NVMe Critical Warning 为 \(warning)，表示控制器报告了关键健康信号。")
            }
            if let spare = metrics.availableSparePercent,
               let threshold = metrics.availableSpareThresholdPercent,
               spare <= threshold {
                raise(.risk, "可用备用空间 \(spare)% 已达到或低于阈值 \(threshold)% 。")
            }
            if let mediaErrors = metrics.mediaErrors, mediaErrors > 0 {
                raise(.risk, "介质与数据完整性错误为 \(mediaErrors)。")
            }
        case .ata:
            if let failing = metrics.ataFailingAttributeCount, failing > 0 {
                raise(.risk, "有 \(failing) 个 ATA SMART 属性已达到厂商阈值。")
            }
            if let pending = metrics.currentPendingSectorCount, pending > 0 {
                raise(.risk, "当前待处理扇区为 \(pending)，存在尚未稳定读取或重映射的扇区。")
            }
            if let uncorrectable = metrics.offlineUncorrectableSectorCount, uncorrectable > 0 {
                raise(.risk, "离线不可校正扇区为 \(uncorrectable)。")
            }
            if let reported = metrics.reportedUncorrectableErrors, reported > 0 {
                raise(.risk, "设备报告的不可校正错误为 \(reported)。")
            }
            if let endToEnd = metrics.endToEndErrorCount, endToEnd > 0 {
                raise(.risk, "端到端数据路径错误为 \(endToEnd)。")
            }
        case .scsi:
            let uncorrected = [
                metrics.scsiReadUncorrectedErrors,
                metrics.scsiWriteUncorrectedErrors,
                metrics.scsiVerifyUncorrectedErrors
            ].compactMap { $0 }.reduce(0, +)
            if uncorrected > 0 {
                raise(.risk, "SCSI 读写或校验不可校正错误合计为 \(uncorrected)。")
            }
        case .unknown:
            if let mediaErrors = metrics.mediaErrors, mediaErrors > 0 {
                raise(.risk, "设备报告的介质错误为 \(mediaErrors)。")
            }
        }
        if let temperature = metrics.temperatureCelsius, temperature >= 80 {
            raise(.risk, "当前温度 \(temperature)°C 过高。")
        }

        if level != .risk {
            if readCompleteness == .coreMissing || readCompleteness == .failed {
                raise(.attention, "读取结果不足，需要重新检测后确认。")
            }
            if let temperature = metrics.temperatureCelsius, temperature >= 65 {
                raise(.attention, "当前温度 \(temperature)°C 偏高。")
            }
            if let used = metrics.percentageUsed, used >= 80 {
                raise(.attention, "寿命消耗 \(used)% 已接近高位。")
            }
            if let spare = metrics.availableSparePercent,
               let threshold = metrics.availableSpareThresholdPercent,
               threshold < 95,
               spare > threshold,
               spare - threshold <= 5 {
                raise(.attention, "可用备用空间 \(spare)% 距阈值 \(threshold)% 较近。")
            }
            if let reallocated = metrics.reallocatedSectorCount, reallocated > 0 {
                raise(.attention, "已重映射扇区为 \(reallocated)，建议结合后续快照观察是否继续增长。")
            }
            if let events = metrics.reallocationEventCount, events > 0 {
                raise(.attention, "扇区重映射事件为 \(events)，建议持续观察趋势。")
            }
            if let timeouts = metrics.commandTimeoutCount, timeouts > 0 {
                raise(.attention, "命令超时累计为 \(timeouts)，可能与硬盘、供电或桥接链路有关。")
            }
            if let crcErrors = metrics.crcErrorCount, crcErrors > 0 {
                raise(.attention, "接口 CRC 错误为 \(crcErrors)，优先检查线材、接口、供电和硬盘盒。")
            }
            if let pastFailures = metrics.ataPastFailureAttributeCount, pastFailures > 0 {
                raise(.attention, "有 \(pastFailures) 个 ATA SMART 属性曾达到厂商阈值。")
            }
            if let defects = metrics.scsiGrownDefectList, defects > 0 {
                raise(.attention, "SCSI 增长缺陷列表为 \(defects)，建议通过后续快照观察变化。")
            }
            if let nonMedium = metrics.scsiNonMediumErrorCount, nonMedium > 0 {
                raise(.attention, "SCSI 非介质错误为 \(nonMedium)，可能来自链路、控制器或设备电子部分。")
            }
            if hasExitBit(smartctlExitStatus, bit: 5),
               (metrics.ataPastFailureAttributeCount ?? 0) == 0 {
                raise(.attention, "smartctl 状态位显示曾有 ATA 预故障属性达到阈值，建议结合属性表和后续趋势复核。")
            }
            if hasExitBit(smartctlExitStatus, bit: 6) {
                raise(.attention, "smartctl 状态位显示设备错误日志含有历史记录，建议查看读取诊断并持续观察。")
            }
            if hasExitBit(smartctlExitStatus, bit: 7) {
                raise(.attention, "smartctl 状态位显示自检日志含有错误记录，建议备份重要数据并进一步检查。")
            }
        }

        if reasons.isEmpty {
            switch metrics.effectiveProtocolFamily {
            case .nvme:
                reasons.append("核心 NVMe SMART 字段正常：SMART 通过、Critical Warning 为 0、备用空间高于阈值、无介质错误。")
            case .ata:
                reasons.append("核心 ATA SMART 字段正常：SMART 通过，未发现待处理、不可校正或关键重映射风险信号。")
            case .scsi:
                reasons.append("核心 SCSI SMART 字段正常：SMART 通过，未发现不可校正读写或校验错误。")
            case .unknown:
                reasons.append("当前可读取的核心 SMART 字段正常。")
            }
        }

        return HealthEvaluation(level: level, reasons: reasons)
    }

    public static func readCompleteness(
        metrics: SmartHealthMetrics,
        messages: [SmartctlMessage],
        exitStatus: Int32?
    ) -> ReadCompletenessEvaluation {
        guard metrics.hasRequiredHealthFields else {
            if metrics.hasCoreFields {
                return ReadCompletenessEvaluation(
                    level: .coreMissing,
                    reasons: ["smartctl 返回了部分字段，但缺少该协议形成健康结论所需的核心 SMART 字段。"]
                )
            }
            return ReadCompletenessEvaluation(
                level: .failed,
                reasons: ["smartctl 未返回可用的核心 SMART 健康数据。"]
            )
        }

        if let exitStatus, hasOnlyHealthOrHistoryFindingBits(exitStatus) {
            return ReadCompletenessEvaluation(
                level: .complete,
                reasons: ["核心健康数据已完整读取；smartctl 状态位报告了设备健康或历史事件，已纳入判定。"]
            )
        }

        let supplementalIssue = containsSupplementalLogIssue(messages)
        if let exitStatus, exitStatus != 0, supplementalIssue {
            return ReadCompletenessEvaluation(
                level: .coreCompleteSupplementalUnavailable,
                reasons: ["核心健康数据已读取成功；附加错误日志明细页不可用，不等同于硬盘故障。"]
            )
        }

        if let exitStatus, exitStatus != 0 {
            return ReadCompletenessEvaluation(
                level: .coreCompleteSupplementalUnavailable,
                reasons: ["核心健康数据已读取成功；smartctl 返回非零状态 \(exitStatus)，详情保留在读取诊断中。"]
            )
        }

        return ReadCompletenessEvaluation(
            level: .complete,
            reasons: ["核心健康数据已完整读取。"]
        )
    }

    public static func containsSupplementalLogIssue(_ messages: [SmartctlMessage]) -> Bool {
        messages.contains { message in
            let lower = message.message.lowercased()
            return lower.contains("error information log failed") ||
                lower.contains("getlogpage failed") ||
                lower.contains("self-test log") ||
                lower.contains("additional log")
        }
    }

    private static func hasExitBit(_ status: Int32?, bit: Int32) -> Bool {
        guard let status, status >= 0 else { return false }
        return (status & (1 << bit)) != 0
    }

    private static func hasOnlyHealthOrHistoryFindingBits(_ status: Int32) -> Bool {
        status > 0 && (status & 0b0000_0111) == 0
    }
}
