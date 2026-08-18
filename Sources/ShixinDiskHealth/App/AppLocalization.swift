import AppKit
import Foundation

enum L10n {
    static func t(_ key: String) -> String {
        let exact = NSLocalizedString(key, bundle: localizedBundle, value: key, comment: "")
        if exact != key { return exact }
        return dynamicTranslation(for: key) ?? key
    }

    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: AppLanguagePreference.currentLocale, arguments: arguments)
    }

    private static var localizedBundle: Bundle {
        guard let resourceIdentifier = AppLanguagePreference.current.resourceIdentifier,
              let path = Bundle.main.path(forResource: resourceIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    private static func dynamicTranslation(for value: String) -> String? {
        for rule in dynamicRules {
            guard let expression = try? NSRegularExpression(pattern: rule.pattern),
                  let match = expression.firstMatch(
                    in: value,
                    range: NSRange(value.startIndex..<value.endIndex, in: value)
                  ) else { continue }

            let arguments: [CVarArg] = (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: value) else { return nil }
                return String(value[range]) as NSString
            }
            let format = NSLocalizedString(
                rule.localizationKey,
                bundle: localizedBundle,
                value: rule.chineseFallback,
                comment: ""
            )
            return String(format: format, locale: AppLanguagePreference.currentLocale, arguments: arguments)
        }
        return nil
    }

    private static let dynamicRules: [(pattern: String, localizationKey: String, chineseFallback: String)] = [
        (#"^NVMe Critical Warning 为 (-?\d+)，表示控制器报告了关键健康信号。$"#, "dynamic.health.nvme_warning", "NVMe Critical Warning 为 %@，表示控制器报告了关键健康信号。"),
        (#"^可用备用空间 (\d+)% 已达到或低于阈值 (\d+)% 。$"#, "dynamic.health.spare_risk", "可用备用空间 %@%% 已达到或低于阈值 %@%%。"),
        (#"^可用备用空间 (\d+)% 距阈值 (\d+)% 较近。$"#, "dynamic.health.spare_attention", "可用备用空间 %@%% 距阈值 %@%% 较近。"),
        (#"^介质与数据完整性错误为 (\d+)。$"#, "dynamic.health.media_errors", "介质与数据完整性错误为 %@。"),
        (#"^设备报告的介质错误为 (\d+)。$"#, "dynamic.health.device_media_errors", "设备报告的介质错误为 %@。"),
        (#"^当前温度 (-?\d+)°C 过高。$"#, "dynamic.health.temperature_risk", "当前温度 %@°C 过高。"),
        (#"^当前温度 (-?\d+)°C 偏高。$"#, "dynamic.health.temperature_attention", "当前温度 %@°C 偏高。"),
        (#"^寿命消耗 (\d+)% 已接近高位。$"#, "dynamic.health.wear_attention", "寿命消耗 %@%% 已接近高位。"),
        (#"^当前待处理扇区为 (\d+)，存在尚未稳定读取或重映射的扇区。$"#, "dynamic.health.ata_pending", "当前待处理扇区为 %@，存在尚未稳定读取或重映射的扇区。"),
        (#"^离线不可校正扇区为 (\d+)。$"#, "dynamic.health.ata_offline_uncorrectable", "离线不可校正扇区为 %@。"),
        (#"^设备报告的不可校正错误为 (\d+)。$"#, "dynamic.health.ata_reported_uncorrectable", "设备报告的不可校正错误为 %@。"),
        (#"^端到端数据路径错误为 (\d+)。$"#, "dynamic.health.ata_end_to_end", "端到端数据路径错误为 %@。"),
        (#"^SCSI 读写或校验不可校正错误合计为 (\d+)。$"#, "dynamic.health.scsi_uncorrected", "SCSI 读写或校验不可校正错误合计为 %@。"),
        (#"^已重映射扇区为 (\d+)，建议结合后续快照观察是否继续增长。$"#, "dynamic.health.ata_reallocated", "已重映射扇区为 %@，建议结合后续快照观察是否继续增长。"),
        (#"^扇区重映射事件为 (\d+)，建议持续观察趋势。$"#, "dynamic.health.ata_reallocation_events", "扇区重映射事件为 %@，建议持续观察趋势。"),
        (#"^命令超时累计为 (\d+)，可能与硬盘、供电或桥接链路有关。$"#, "dynamic.health.ata_timeouts", "命令超时累计为 %@，可能与硬盘、供电或桥接链路有关。"),
        (#"^接口 CRC 错误为 (\d+)，优先检查线材、接口、供电和硬盘盒。$"#, "dynamic.health.ata_crc", "接口 CRC 错误为 %@，优先检查线材、接口、供电和硬盘盒。"),
        (#"^SCSI 增长缺陷列表为 (\d+)，建议通过后续快照观察变化。$"#, "dynamic.health.scsi_defects", "SCSI 增长缺陷列表为 %@，建议通过后续快照观察变化。"),
        (#"^SCSI 非介质错误为 (\d+)，可能来自链路、控制器或设备电子部分。$"#, "dynamic.health.scsi_non_medium", "SCSI 非介质错误为 %@，可能来自链路、控制器或设备电子部分。"),
        (#"^核心健康数据已读取成功；smartctl 返回非零状态 (-?\d+)，详情保留在读取诊断中。$"#, "dynamic.read.nonzero_exit", "核心健康数据已读取成功；smartctl 返回非零状态 %@，详情保留在读取诊断中。"),
        (#"^(/dev/disk\d+) 不存在$"#, "dynamic.failure.device_missing_title", "%@ 不存在"),
        (#"^未发现所选硬盘设备节点 (/dev/disk\d+)。$"#, "dynamic.failure.device_missing_message", "未发现所选硬盘设备节点 %@。"),
        (#"^(.+) 当前不是可读取 SMART 的本地 whole-disk 设备。$"#, "dynamic.failure.unsupported_target", "%@ 当前不是可读取 SMART 的本地 whole-disk 设备。"),
        (#"^只读系统查询在 (\d+) 秒内没有完成，已终止。$"#, "dynamic.process.timeout", "只读系统查询在 %@ 秒内没有完成，已终止。"),
        (#"^外部工具输出超过安全上限 (\d+) bytes，已拒绝继续解析。$"#, "dynamic.process.output_limit", "外部工具输出超过安全上限 %@ bytes，已拒绝继续解析。"),
        (#"^有 (\d+) 个 ATA SMART 属性已达到厂商阈值。$"#, "dynamic.health.ata_failing", "有 %@ 个 ATA SMART 属性已达到厂商阈值。"),
        (#"^有 (\d+) 个 ATA SMART 属性曾达到厂商阈值。$"#, "dynamic.health.ata_failed_in_past", "有 %@ 个 ATA SMART 属性曾达到厂商阈值。"),
        (#"^smartctl 返回的设备为 (.+)，与所选目标 (.+) 不一致，已拒绝使用该结果。$"#, "dynamic.failure.device_mismatch", "smartctl 返回的设备为 %@，与所选目标 %@ 不一致，已拒绝使用该结果。"),
        (#"^已保存快照：(.+)$"#, "dynamic.snapshot.saved", "已保存快照：%@"),
        (#"^设备类型：(.+)$"#, "dynamic.diagnostic.device_type", "设备类型：%@"),
        (#"^请检查应用支持目录是否可写：(.+)$"#, "dynamic.recovery.app_support", "请检查应用支持目录是否可写：%@"),
        (#"^请检查历史记录文件权限：(.+)$"#, "dynamic.recovery.snapshot_history", "请检查历史记录文件权限：%@"),
        (#"^请检查速度测试历史文件权限：(.+)$"#, "dynamic.recovery.speed_history", "请检查速度测试历史文件权限：%@")
    ]
}

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case english
    case japanese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L10n.t("跟随系统")
        case .zhHans: "简体中文"
        case .english: "English"
        case .japanese: "日本語"
        }
    }

    var appleLanguages: [String]? {
        switch self {
        case .system: nil
        case .zhHans: ["zh-Hans"]
        case .english: ["en"]
        case .japanese: ["ja"]
        }
    }

    var resourceIdentifier: String? {
        switch self {
        case .system: nil
        case .zhHans: "zh-Hans"
        case .english: "en"
        case .japanese: "ja"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .system:
            Locale.autoupdatingCurrent.identifier
        case .zhHans:
            "zh-Hans"
        case .english:
            "en"
        case .japanese:
            "ja"
        }
    }

    static var current: AppLanguagePreference {
        let rawValue = UserDefaults.standard.string(forKey: "appLanguagePreference") ?? AppLanguagePreference.system.rawValue
        return AppLanguagePreference(rawValue: rawValue) ?? .system
    }

    static var currentLocale: Locale {
        Locale(identifier: current.localeIdentifier)
    }

    static func locale(for rawValue: String) -> Locale {
        let preference = AppLanguagePreference(rawValue: rawValue) ?? .system
        return Locale(identifier: preference.localeIdentifier)
    }
}

enum AppLanguageController {
    static func applyStoredPreference() {
        apply(AppLanguagePreference.current)
    }

    static func apply(_ preference: AppLanguagePreference) {
        if let languages = preference.appleLanguages {
            UserDefaults.standard.set(languages, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}

enum AppRestarter {
    @MainActor
    static func restartApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else {
                NSSound.beep()
                return
            }
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
