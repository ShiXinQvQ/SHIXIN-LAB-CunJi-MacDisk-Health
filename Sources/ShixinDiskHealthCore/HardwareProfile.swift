import Darwin
import Foundation

public struct HardwareInfoRow: Identifiable, Codable, Equatable, Sendable {
    public var title: String
    public var value: String
    public var detail: String?
    public var help: String
    public var systemImage: String

    public var id: String { "\(title)-\(value)" }

    public init(title: String, value: String, detail: String? = nil, help: String? = nil, systemImage: String) {
        self.title = title
        self.value = value
        self.detail = detail
        self.help = help ?? HardwareInfoRow.defaultHelp(for: title)
        self.systemImage = systemImage
    }

    private static func defaultHelp(for title: String) -> String {
        switch title {
        case "SoC":
            return "SoC 是 Apple Silicon 的主芯片，CPU、GPU、内存控制器和很多协处理器都集成在这里。"
        case "CPU 内核":
            return "这里显示 CPU 物理核心组成。性能核心负责高负载计算，效率核心负责低功耗任务；逻辑核心是系统调度看到的可执行单元。"
        case "GPU 内核":
            return "这里显示 Apple 芯片集成 GPU 的核心数量。图形、Metal compute 和部分视频/图像任务会使用它。"
        case "系统内存":
            return "Apple Silicon 使用统一内存，CPU 和 GPU 共享同一套高速内存池。"
        case "系统版本":
            return "当前正在运行的 macOS 版本与构建号。系统版本会影响系统接口可见性。"
        case "内核版本":
            return "Darwin 是 macOS 的底层内核版本，适合排查系统级行为差异。"
        case "自启动以来的时间":
            return "Mac 从上次开机或重启到现在经过的时间。"
        case "隐私处理":
            return "默认隐藏序列号、UDID、平台 UUID 等可识别设备的信息。可以在设置里手动开启显示。"
        default:
            return "这是从 macOS 系统接口读取到的本机配置项，只用于本机展示，不会上传。"
        }
    }
}

public struct HardwareInfoSection: Identifiable, Codable, Equatable, Sendable {
    public var title: String
    public var systemImage: String
    public var rows: [HardwareInfoRow]

    public var id: String { title }

    public init(title: String, systemImage: String, rows: [HardwareInfoRow]) {
        self.title = title
        self.systemImage = systemImage
        self.rows = rows
    }
}

public struct HardwareProfile: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var headlineRows: [HardwareInfoRow]
    public var sections: [HardwareInfoSection]
    public var message: String?

    public init(
        generatedAt: Date = Date(),
        headlineRows: [HardwareInfoRow],
        sections: [HardwareInfoSection],
        message: String? = nil
    ) {
        self.generatedAt = generatedAt
        self.headlineRows = headlineRows
        self.sections = sections
        self.message = message
    }

    public static var loading: HardwareProfile {
        HardwareProfile(
            headlineRows: [
                HardwareInfoRow(title: "SoC", value: "读取中", systemImage: "cpu"),
                HardwareInfoRow(title: "CPU 内核", value: "读取中", systemImage: "circle.grid.cross"),
                HardwareInfoRow(title: "GPU 内核", value: "读取中", systemImage: "rectangle.3.group"),
                HardwareInfoRow(title: "系统内存", value: "读取中", systemImage: "memorychip")
            ],
            sections: []
        )
    }
}

public enum HardwareProfileReader {
    public static func read(showPrivateIdentifiers: Bool = false) async -> HardwareProfile {
        let profiler = await SystemProfilerSnapshot.read()
        let hardware = profiler.hardware
        let displays = profiler.displays
        let storages = profiler.storages

        let chip = hardware.string("chip_type")
            ?? sysctlString("machdep.cpu.brand_string")
            ?? "Apple Silicon"
        let modelName = hardware.string("machine_name") ?? "Mac"
        let modelIdentifier = hardware.string("machine_model") ?? sysctlString("hw.model") ?? HardwareText.unknown
        let modelNumber = hardware.string("model_number") ?? HardwareText.notDisclosed
        let memory = hardware.string("physical_memory")
            ?? sysctlUInt64("hw.memsize").map(HardwareValueFormatting.bytes)
            ?? HardwareText.unknown
        let memoryBytes = sysctlUInt64("hw.memsize").map(HardwareValueFormatting.bytes) ?? memory
        let logicalCores = sysctlInt("hw.logicalcpu")
        let physicalCores = sysctlInt("hw.physicalcpu")
        let performanceCores = sysctlInt("hw.perflevel0.physicalcpu")
        let efficiencyCores = sysctlInt("hw.perflevel1.physicalcpu")
        let cpuText = cpuCoreText(logical: logicalCores, physical: physicalCores, performance: performanceCores, efficiency: efficiencyCores)
        let cpuHeadlineValue = cpuHeadlineCoreText(logical: logicalCores, physical: physicalCores, performance: performanceCores, efficiency: efficiencyCores)
        let cpuHeadlineDetail = cpuHeadlineCoreDetail(logical: logicalCores, performance: performanceCores, efficiency: efficiencyCores)
        let cpuBrand = sysctlString("machdep.cpu.brand_string") ?? chip
        let gpuCores = gpuCoreText(displays.first?.string("sppci_cores"))

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let kernelVersion = sysctlString("kern.osrelease") ?? HardwareText.unknown
        let firmware = hardware.string("boot_rom_version") ?? HardwareText.unknown
        let osLoader = hardware.string("os_loader_version") ?? HardwareText.unknown
        let uptime = HardwareValueFormatting.seconds(ProcessInfo.processInfo.systemUptime)
        let hostName = Host.current().localizedName ?? HardwareText.unknown
        let serial = hardware.string("serial_number") ?? HardwareText.notRead
        let udid = hardware.string("provisioning_UDID") ?? HardwareText.notRead
        let platformUUID = hardware.string("platform_UUID") ?? HardwareText.notRead

        let primaryStorage = storages.first(where: { $0.dictionary("physical_drive")?.string("is_internal_disk") == "yes" }) ?? storages.first
        let drive = primaryStorage?.dictionary("physical_drive")
        let driveName = drive?.string("device_name") ?? HardwareText.unknown
        let driveProtocol = drive?.string("protocol") ?? HardwareText.unknown
        let driveHealth = drive?.string("smart_status") ?? HardwareText.unknown
        let driveSize = uint64Value(primaryStorage, "size_in_bytes").map(HardwareValueFormatting.bytes) ?? HardwareText.unknown
        let driveFree = uint64Value(primaryStorage, "free_space_in_bytes").map(HardwareValueFormatting.bytes) ?? HardwareText.unknown

        var displayRows: [HardwareInfoRow] = []
        if let gpu = displays.first {
            displayRows.append(HardwareInfoRow(title: "图形处理器", value: gpu.string("sppci_model") ?? chip, detail: "Apple Metal", help: "当前系统报告的图形处理器名称。Apple Silicon 的 GPU 集成在 SoC 内。", systemImage: "rectangle.3.group"))
            displayRows.append(HardwareInfoRow(title: "GPU 内核", value: gpuCores, detail: gpu.string("spdisplays_mtlgpufamilysupport") ?? "Metal", help: "GPU 核心数量越多，Metal 图形和 compute 并行能力通常越强。", systemImage: "square.grid.3x3"))
            let connectedDisplays = dictionaryArray(gpu, "spdisplays_ndrvs")
            if connectedDisplays.isEmpty {
                displayRows.append(HardwareInfoRow(title: "显示器", value: HardwareText.noExternalDisplay, help: "system_profiler 当前没有报告在线显示器。", systemImage: "display"))
            } else {
                for (index, display) in connectedDisplays.prefix(4).enumerated() {
                    let name = display.string("_name") ?? HardwareText.display(index + 1)
                    let resolution = display.string("spdisplays_resolution") ?? display.string("_spdisplays_pixels")
                    displayRows.append(HardwareInfoRow(title: name, value: resolution ?? HardwareText.connected, detail: display.string("spdisplays_main") == "spdisplays_yes" ? HardwareText.mainDisplay : nil, help: "当前连接的显示器及分辨率/刷新率。高刷新率和高分辨率会增加 GPU 显示管线负载。", systemImage: "display"))
                }
            }
        }

        let headlineRows = [
            HardwareInfoRow(title: "SoC", value: headlineChipName(chip), detail: modelIdentifier, help: "本机 Apple Silicon 主芯片型号。", systemImage: "cpu"),
            HardwareInfoRow(title: "CPU 内核", value: cpuHeadlineValue, detail: cpuHeadlineDetail, help: "性能核心适合高负载计算，能效核心更省电。", systemImage: "circle.grid.cross"),
            HardwareInfoRow(title: "GPU 内核", value: gpuCores, detail: "Metal GPU", help: "Metal GPU 会使用这些 GPU 核心执行图形和 compute 任务。", systemImage: "rectangle.3.group"),
            HardwareInfoRow(title: "系统内存", value: memory, detail: HardwareText.unifiedMemory, help: "统一内存由 CPU/GPU 共享，容量会影响大型渲染、模型和素材任务。", systemImage: "memorychip")
        ]

        var privacyRows = [
            HardwareInfoRow(title: "隐私处理", value: showPrivateIdentifiers ? HardwareText.privateIdentifiersShown : HardwareText.privateIdentifiersHidden, help: "这些字段可以识别具体设备，默认隐藏；开启后仅在本机界面显示，不会上传。", systemImage: showPrivateIdentifiers ? "eye" : "eye.slash")
        ]
        privacyRows.append(HardwareInfoRow(title: "序列号", value: showPrivateIdentifiers ? serial : maskedIdentifier(serial), help: "硬件序列号可以唯一识别这台 Mac，分享截图前请谨慎。隐藏时保留字段位置并用星号显示。", systemImage: "number"))
        privacyRows.append(HardwareInfoRow(title: "Provisioning UDID", value: showPrivateIdentifiers ? udid : maskedIdentifier(udid), help: "设备 UDID 用于开发和配置描述文件场景，也属于敏感设备标识。隐藏时保留字段位置并用星号显示。", systemImage: "person.text.rectangle"))
        privacyRows.append(HardwareInfoRow(title: "平台 UUID", value: showPrivateIdentifiers ? platformUUID : maskedIdentifier(platformUUID), help: "平台 UUID 是系统层面的设备唯一标识之一，默认隐藏。隐藏时保留字段位置并用星号显示。", systemImage: "key"))

        let sections = [
            HardwareInfoSection(title: "系统软件信息", systemImage: "macwindow", rows: [
                HardwareInfoRow(title: "系统版本", value: osVersion, help: "当前 macOS 版本。不同版本可能影响系统接口可见性。", systemImage: "apple.logo"),
                HardwareInfoRow(title: "内核版本", value: "Darwin \(kernelVersion)", help: "Darwin 内核版本，适合与第三方工具或崩溃日志对照。", systemImage: "terminal"),
                HardwareInfoRow(title: "自启动以来的时间", value: uptime, help: "Mac 从上次开机或重启到现在经过的时间。", systemImage: "clock.arrow.circlepath"),
                HardwareInfoRow(title: "本机名称", value: hostName, help: "系统共享名称，不等同于硬件型号。", systemImage: "network")
            ]),
            HardwareInfoSection(title: "隐私与设备标识", systemImage: "lock.shield", rows: privacyRows),
            HardwareInfoSection(title: "处理器与内存", systemImage: "cpu", rows: [
                HardwareInfoRow(title: "SoC", value: chip, help: "Apple Silicon 主芯片，CPU/GPU/统一内存控制器都在同一封装中。", systemImage: "cpu"),
                HardwareInfoRow(title: "CPU 品牌字符串", value: cpuBrand, help: "系统底层报告的 CPU/SoC 名称。", systemImage: "tag"),
                HardwareInfoRow(title: "CPU 内核", value: cpuText, detail: HardwareText.logicalCoreDetail(logicalCores), help: "性能核心和效率核心的数量决定不同负载下的调度与功耗上限。", systemImage: "circle.grid.cross"),
                HardwareInfoRow(title: "物理核心", value: physicalCores.map(String.init) ?? HardwareText.unknown, help: "实际 CPU 核心数量，不包含线程或虚拟核心概念。Apple Silicon 通常没有超线程。", systemImage: "cpu"),
                HardwareInfoRow(title: "逻辑核心", value: logicalCores.map(String.init) ?? HardwareText.unknown, help: "系统调度器看到的可并行执行单元数量。", systemImage: "square.grid.3x3"),
                HardwareInfoRow(title: "性能核心", value: performanceCores.map(String.init) ?? HardwareText.unknown, help: "高性能核心，长时间高负载主要依赖它们拉高功耗。", systemImage: "speedometer"),
                HardwareInfoRow(title: "效率核心", value: efficiencyCores.map(String.init) ?? HardwareText.unknown, help: "低功耗核心，适合后台和轻任务，也会参与满核心负载。", systemImage: "leaf"),
                HardwareInfoRow(title: "系统内存", value: memory, detail: memoryBytes, help: "统一内存容量，CPU/GPU 共享，和传统独立显存架构不同。", systemImage: "memorychip")
            ]),
            HardwareInfoSection(title: "系统硬件信息", systemImage: "cpu", rows: [
                HardwareInfoRow(title: "型号名称", value: modelName, help: "产品线名称，例如 MacBook Pro。", systemImage: "laptopcomputer"),
                HardwareInfoRow(title: "型号标识符", value: modelIdentifier, help: "苹果内部硬件型号标识，例如 Mac15,8；排查兼容性时很有用。", systemImage: "number"),
                HardwareInfoRow(title: "型号", value: modelNumber, help: "销售/配置型号，不同地区和配置可能不同。", systemImage: "tag"),
                HardwareInfoRow(title: "系统固件版本", value: firmware, help: "底层固件版本，系统更新可能会改变它。", systemImage: "shippingbox"),
                HardwareInfoRow(title: "操作系统加载器版本", value: osLoader, help: "启动链路相关版本，通常用于底层诊断。", systemImage: "arrow.down.circle")
            ]),
            HardwareInfoSection(title: "图形与显示", systemImage: "display.2", rows: displayRows),
            HardwareInfoSection(title: "内置存储", systemImage: "internaldrive", rows: [
                HardwareInfoRow(title: "设备", value: driveName, help: "内置 SSD 的设备名称，来自系统存储信息。", systemImage: "internaldrive"),
                HardwareInfoRow(title: "协议", value: driveProtocol, help: "存储控制器与系统通信使用的协议。Apple Silicon 内置 SSD 常见为 Apple Fabric。", systemImage: "point.3.connected.trianglepath.dotted"),
                HardwareInfoRow(title: "容量", value: driveSize, detail: HardwareText.available(driveFree), help: "当前系统卷所在内置存储容量和可用空间。", systemImage: "externaldrive"),
                HardwareInfoRow(title: "SMART 状态", value: driveHealth, help: "系统报告的存储健康状态；这里只做配置概览，不替代硬盘健康工具的完整 SMART 报告。", systemImage: "checkmark.seal")
            ])
        ].filter { !$0.rows.isEmpty }

        return HardwareProfile(
            headlineRows: headlineRows,
            sections: sections,
            message: profiler.message
        )
    }

    private static func cpuCoreText(logical: Int?, physical: Int?, performance: Int?, efficiency: Int?) -> String {
        if let performance, let efficiency {
            return HardwareText.performanceEfficiencyCores(performance: performance, efficiency: efficiency)
        }
        if let physical {
            return HardwareText.cores(physical)
        }
        if let logical {
            return HardwareText.logicalCores(logical)
        }
        return HardwareText.unknown
    }

    private static func cpuHeadlineCoreText(logical: Int?, physical: Int?, performance: Int?, efficiency: Int?) -> String {
        if let physical {
            return HardwareText.cores(physical)
        }
        if let performance, let efficiency {
            return HardwareText.cores(performance + efficiency)
        }
        if let logical {
            return HardwareText.cores(logical)
        }
        return HardwareText.unknown
    }

    private static func cpuHeadlineCoreDetail(logical: Int?, performance: Int?, efficiency: Int?) -> String {
        if let performance, let efficiency {
            return HardwareText.performanceEfficiencyDetail(performance: performance, efficiency: efficiency)
        }
        if let logical {
            return HardwareText.logicalCoreDetail(logical)
        }
        return HardwareText.coreLayoutUnknown
    }

    private static func gpuCoreText(_ rawValue: String?) -> String {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return HardwareText.unknown }
        if value.contains("核") || value.localizedCaseInsensitiveContains("core") {
            return value
        }
        return HardwareText.gpuCores(value)
    }

    private static func headlineChipName(_ rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let applePrefix = "Apple "
        guard value.hasPrefix(applePrefix) else { return value }
        return String(value.dropFirst(applePrefix.count))
    }

    private static func maskedIdentifier(_ value: String) -> String {
        guard !value.isEmpty, value != HardwareText.notRead else { return "********" }
        return String(value.map { character in
            character == "-" ? "-" : "*"
        })
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private static func uint64Value(_ dictionary: [String: Any]?, _ key: String) -> UInt64? {
        guard let value = dictionary?[key] else { return nil }
        if let value = value as? UInt64 { return value }
        if let value = value as? UInt { return UInt64(value) }
        if let value = value as? Int { return UInt64(value) }
        if let value = value as? Int64 { return UInt64(value) }
        if let value = value as? NSNumber { return value.uint64Value }
        if let value = value as? String { return UInt64(value) }
        return nil
    }

    private static func dictionaryArray(_ dictionary: [String: Any], _ key: String) -> [[String: Any]] {
        dictionary[key] as? [[String: Any]] ?? []
    }
}

private enum HardwareValueFormatting {
    static func bytes(_ bytes: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = displayLocale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1

        let value = Double(bytes)
        if value >= 1_000_000_000_000 {
            let text = formatter.string(from: NSNumber(value: value / 1_000_000_000_000)) ?? String(format: "%.1f", value / 1_000_000_000_000)
            return "\(text) TB"
        }
        let text = formatter.string(from: NSNumber(value: value / 1_000_000_000)) ?? String(format: "%.1f", value / 1_000_000_000)
        return "\(text) GB"
    }

    static func seconds(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    private static var displayLocale: Locale {
        switch UserDefaults.standard.string(forKey: "appLanguagePreference") {
        case "zhHans":
            Locale(identifier: "zh-Hans")
        case "english":
            Locale(identifier: "en")
        case "japanese":
            Locale(identifier: "ja")
        default:
            Locale.autoupdatingCurrent
        }
    }
}

private enum HardwareText {
    private enum Language {
        case zhHans
        case english
        case japanese
    }

    static var unknown: String {
        switch language {
        case .english: "Unknown"
        case .japanese: "不明"
        case .zhHans: "未知"
        }
    }

    static var notRead: String {
        switch language {
        case .english: "Not read"
        case .japanese: "未取得"
        case .zhHans: "未读取"
        }
    }

    static var notDisclosed: String {
        switch language {
        case .english: "Not disclosed"
        case .japanese: "非公開"
        case .zhHans: "未公开"
        }
    }

    static var unifiedMemory: String {
        switch language {
        case .english: "Unified Memory"
        case .japanese: "ユニファイドメモリ"
        case .zhHans: "统一内存"
        }
    }

    static var noExternalDisplay: String {
        switch language {
        case .english: "No external display read"
        case .japanese: "外部ディスプレイ未取得"
        case .zhHans: "未读取到外接显示器"
        }
    }

    static var connected: String {
        switch language {
        case .english: "Connected"
        case .japanese: "接続済み"
        case .zhHans: "已连接"
        }
    }

    static var mainDisplay: String {
        switch language {
        case .english: "Main Display"
        case .japanese: "メインディスプレイ"
        case .zhHans: "主显示器"
        }
    }

    static var privateIdentifiersShown: String {
        switch language {
        case .english: "Full device identifiers shown"
        case .japanese: "完全なデバイスIDを表示中"
        case .zhHans: "已显示完整设备标识"
        }
    }

    static var privateIdentifiersHidden: String {
        switch language {
        case .english: "Serial number / UDID / platform UUID hidden"
        case .japanese: "シリアル番号 / UDID / プラットフォームUUID 非表示"
        case .zhHans: "已隐藏序列号 / UDID / 平台 UUID"
        }
    }

    static var coreLayoutUnknown: String {
        switch language {
        case .english: "Core layout unknown"
        case .japanese: "コア構成不明"
        case .zhHans: "核心分配未知"
        }
    }

    static func cores(_ count: Int) -> String {
        switch language {
        case .english: "\(count) cores"
        case .japanese: "\(count) コア"
        case .zhHans: "\(count) 核心"
        }
    }

    static func gpuCores(_ value: String) -> String {
        switch language {
        case .english: "\(value) cores"
        case .japanese: "\(value) コア"
        case .zhHans: "\(value) 内核"
        }
    }

    static func logicalCores(_ count: Int) -> String {
        switch language {
        case .english: "\(count) logical cores"
        case .japanese: "\(count) 論理コア"
        case .zhHans: "\(count) 逻辑核心"
        }
    }

    static func logicalCoreDetail(_ count: Int?) -> String {
        guard let count else { return unknown }
        switch language {
        case .english:
            return "Logical cores \(count)"
        case .japanese:
            return "論理コア \(count)"
        case .zhHans:
            return "逻辑核心 \(count)"
        }
    }

    static func performanceEfficiencyDetail(performance: Int, efficiency: Int) -> String {
        switch language {
        case .english: "\(performance) performance + \(efficiency) efficiency"
        case .japanese: "\(performance) 高性能 + \(efficiency) 高効率"
        case .zhHans: "\(performance) 性能 + \(efficiency) 能效"
        }
    }

    static func performanceEfficiencyCores(performance: Int, efficiency: Int) -> String {
        switch language {
        case .english: "\(performance + efficiency) cores (\(performance) performance + \(efficiency) efficiency)"
        case .japanese: "\(performance + efficiency) コア（\(performance) 高性能 + \(efficiency) 高効率）"
        case .zhHans: "\(performance + efficiency) 核心（\(performance) 性能 + \(efficiency) 效率）"
        }
    }

    static func display(_ index: Int) -> String {
        switch language {
        case .english: "Display \(index)"
        case .japanese: "ディスプレイ \(index)"
        case .zhHans: "显示器 \(index)"
        }
    }

    static func available(_ value: String) -> String {
        switch language {
        case .english: "Free \(value)"
        case .japanese: "空き \(value)"
        case .zhHans: "可用 \(value)"
        }
    }

    private static var language: Language {
        switch UserDefaults.standard.string(forKey: "appLanguagePreference") {
        case "english":
            return .english
        case "japanese":
            return .japanese
        case "zhHans":
            return .zhHans
        default:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
            if preferred.hasPrefix("ja") { return .japanese }
            if preferred.hasPrefix("en") { return .english }
            return .zhHans
        }
    }
}

private struct SystemProfilerSnapshot {
    var hardware: [String: Any]
    var displays: [[String: Any]]
    var storages: [[String: Any]]
    var message: String?

    static func read() async -> SystemProfilerSnapshot {
        do {
            let output = try await ProcessExecutor.run(
                executableURL: URL(fileURLWithPath: "/usr/sbin/system_profiler"),
                arguments: ["SPHardwareDataType", "SPDisplaysDataType", "SPStorageDataType", "-json"],
                timeoutSeconds: 30,
                maximumOutputBytes: 32 * 1_024 * 1_024
            )
            let errorText = String(data: output.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard output.exitStatus == 0, !output.stdout.isEmpty else {
                return SystemProfilerSnapshot(hardware: [:], displays: [], storages: [], message: errorText ?? "system_profiler 未返回数据")
            }
            let json = try JSONSerialization.jsonObject(with: output.stdout) as? [String: Any]
            return SystemProfilerSnapshot(
                hardware: (json?["SPHardwareDataType"] as? [[String: Any]])?.first ?? [:],
                displays: json?["SPDisplaysDataType"] as? [[String: Any]] ?? [],
                storages: json?["SPStorageDataType"] as? [[String: Any]] ?? [],
                message: nil
            )
        } catch {
            return SystemProfilerSnapshot(hardware: [:], displays: [], storages: [], message: error.localizedDescription)
        }
    }
}
