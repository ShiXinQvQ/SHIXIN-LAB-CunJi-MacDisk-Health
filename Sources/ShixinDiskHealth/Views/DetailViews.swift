import ShixinDiskHealthCore
import SwiftUI

struct DetailSectionsView: View {
    var snapshot: SmartSnapshot
    var showSerial: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        deviceIdentityCard
                        temperatureCard
                        protocolSpecificCard
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(alignment: .leading, spacing: 14) {
                        if hasNVMeReadWriteStatistics {
                            readWriteCard
                        }
                        powerAndControllerCard
                        reliabilityCard
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                VStack(alignment: .leading, spacing: 14) {
                    deviceIdentityCard
                    protocolSpecificCard
                    temperatureCard
                    if hasNVMeReadWriteStatistics {
                        readWriteCard
                    }
                    powerAndControllerCard
                    reliabilityCard
                }
            }

            DiagnosticCard(snapshot: snapshot)
        }
    }

    private var deviceIdentityCard: some View {
        DetailCard(title: "设备身份", systemImage: "internaldrive") {
            KeyValueRow(
                title: "设备",
                value: snapshot.diskDevicePath ?? snapshot.device.deviceName,
                helpTitle: "Device Node",
                help: "这里显示本次 SMART 读取使用的 whole-disk 设备节点。App 只允许读取枚举到的 /dev/diskN，不允许读取分区、rdisk 或任意路径。"
            )
            KeyValueRow(
                title: "目标",
                value: snapshot.diskDisplayName ?? snapshot.device.modelName ?? snapshot.device.deviceName,
                helpTitle: "Disk Target",
                help: "当前快照所属的硬盘目标。历史记录会按这个磁盘身份分组，避免不同硬盘的趋势混在一起。"
            )
            KeyValueRow(
                title: "连接",
                value: snapshot.diskConnectionKind.map { L10n.t($0.rawValue) } ?? L10n.t("未返回"),
                helpTitle: "Connection",
                help: "区分内置硬盘、外置本地硬盘和网络卷。网络卷只能做普通文件测速，不能读取 SMART。"
            )
            KeyValueRow(
                title: "型号",
                value: snapshot.device.modelName ?? "未返回",
                helpTitle: "Model Name",
                help: "smartctl 从控制器返回的硬盘型号。它通常是硬件/固件层面的名称，可能不同于系统设置或商品页面里的营销名称。"
            )
            KeyValueRow(
                title: "序列号",
                value: serialText,
                monospaced: showSerial,
                helpTitle: "Serial Number",
                help: "硬盘硬件序列号。界面默认隐藏；历史快照本机会保存完整值。导出报告前会提醒，因为报告可能包含可识别设备的信息。"
            )
            KeyValueRow(
                title: "固件",
                value: snapshot.device.firmwareVersion ?? "未返回",
                helpTitle: "Firmware Version",
                help: "硬盘或存储控制器固件版本，不是 macOS 系统版本。"
            )
            KeyValueRow(
                title: "协议",
                value: snapshot.device.protocolName ?? "未返回",
                helpTitle: "Protocol",
                help: "硬盘与系统通信使用的存储协议，例如 NVMe、ATA/SATA 或 SCSI/SAS。协议只说明通信类型，不直接代表健康好坏。"
            )
            switch snapshot.metrics.effectiveProtocolFamily {
            case .nvme:
                KeyValueRow(title: "NVMe 版本", value: snapshot.device.nvmeVersion ?? "未返回")
            case .ata:
                if let ataVersion = snapshot.device.ataVersion {
                    KeyValueRow(title: "ATA 版本", value: ataVersion)
                }
                if let sataVersion = snapshot.device.sataVersion {
                    KeyValueRow(title: "SATA 版本", value: sataVersion)
                }
            case .scsi:
                KeyValueRow(title: "SCSI 版本", value: snapshot.device.scsiVersion ?? "未返回")
            case .unknown:
                EmptyView()
            }
            if let rotationRate = snapshot.device.rotationRateRPM {
                KeyValueRow(title: "转速", value: rotationRate == 0 ? L10n.t("固态设备") : "\(rotationRate) RPM")
            }
        }
    }

    @ViewBuilder
    private var protocolSpecificCard: some View {
        switch snapshot.metrics.effectiveProtocolFamily {
        case .nvme:
            lifetimeCard
        case .ata:
            ataAttributesCard
        case .scsi:
            scsiErrorCard
        case .unknown:
            DetailCard(title: "协议健康字段", systemImage: "questionmark.folder") {
                Text("当前协议只返回了有限的通用 SMART 字段；App 不会把未知字段推断成健康。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lifetimeCard: some View {
        DetailCard(title: "SSD 寿命与备用空间", systemImage: "gauge.with.dots.needle.50percent") {
            KeyValueRow(
                title: "寿命消耗",
                value: SmartFormatting.percent(snapshot.metrics.percentageUsed),
                helpTitle: "Percentage Used",
                help: "NVMe 设备估算的寿命消耗百分比，通常基于厂商耐久度模型。0% 不代表完全没有写入；100% 也不等于立刻损坏，但表示已达到或超过设计耐久度参考线。"
            )
            KeyValueRow(
                title: "可用备用空间",
                value: SmartFormatting.percent(snapshot.metrics.availableSparePercent),
                helpTitle: "Available Spare",
                help: "SSD 仍可用于替代坏块或维持可靠性的备用空间比例。数值越高越好；低于或等于阈值时应重点关注。"
            )
            KeyValueRow(
                title: "备用空间阈值",
                value: SmartFormatting.percent(snapshot.metrics.availableSpareThresholdPercent),
                helpTitle: "Available Spare Threshold",
                help: "设备定义的备用空间警戒线。比较时应看“可用备用空间”是否低于或等于这个阈值，而不是单独看阈值本身。"
            )
            KeyValueRow(
                title: "Critical Warning",
                value: SmartFormatting.integer(snapshot.metrics.criticalWarning),
                helpTitle: "Critical Warning",
                help: "NVMe 关键警告位掩码。0 通常表示没有关键警告；非 0 可能代表备用空间、温度、可靠性或只读状态等问题，需要结合其他字段判断。"
            )
        }
    }

    private var temperatureCard: some View {
        DetailCard(title: "温度", systemImage: "thermometer.medium") {
            KeyValueRow(
                title: "当前温度",
                value: SmartFormatting.celsius(snapshot.metrics.temperatureCelsius),
                helpTitle: "SMART Temperature",
                help: "硬盘或控制器报告的当前温度，不是 CPU、机身外壳或环境温度。短时间升高常见于大量读写；长期高温更需要关注散热与负载。"
            )
        }
    }

    private var readWriteCard: some View {
        DetailCard(title: "读写统计", systemImage: "arrow.up.arrow.down") {
            KeyValueRow(
                title: "累计读取量",
                value: SmartFormatting.byteString(snapshot.metrics.readBytes),
                helpTitle: "Data Units Read",
                help: "NVMe Data Units Read 换算值。每个 data unit 按 512,000 bytes 计算。它是设备累计读取量，通常不等于 Finder 文件大小或某个 App 的单次读盘量。"
            )
            KeyValueRow(
                title: "累计写入量",
                value: SmartFormatting.byteString(snapshot.metrics.writtenBytes),
                helpTitle: "Data Units Written",
                help: "NVMe Data Units Written 换算值。每个 data unit 按 512,000 bytes 计算。它是 SSD 寿命评估的重要参考，但不能单独决定健康状态。"
            )
            KeyValueRow(
                title: "主机读取命令数",
                value: SmartFormatting.integer(snapshot.metrics.hostReads),
                helpTitle: "Host Read Commands",
                help: "主机向 SSD 发出的读取命令累计次数。它是命令数量，不是 GB/TB；一次命令的数据量可能大小不同。"
            )
            KeyValueRow(
                title: "主机写入命令数",
                value: SmartFormatting.integer(snapshot.metrics.hostWrites),
                helpTitle: "Host Write Commands",
                help: "主机向 SSD 发出的写入命令累计次数。它和累计写入量相关，但不是同一个指标，也不等同于用户保存文件的次数。"
            )
        }
    }

    private var powerAndControllerCard: some View {
        DetailCard(title: "电源与控制器事件", systemImage: "bolt.badge.clock") {
            KeyValueRow(
                title: "通电小时",
                value: SmartFormatting.integer(snapshot.metrics.powerOnHours),
                helpTitle: "Power On Hours",
                help: "硬盘或存储控制器累计通电时间。该值可能不包含设备处于非工作电源状态的时间，因此不能直接等同于整台 Mac 的总使用时间。"
            )
            if snapshot.metrics.powerCycles != nil {
                KeyValueRow(
                    title: "电源循环次数",
                    value: SmartFormatting.integer(snapshot.metrics.powerCycles),
                    helpTitle: "电源循环次数",
                    help: "SSD 控制器累计经历上电初始化的次数。关机、重启或某些深度电源状态可能使其增加；数值本身不代表故障，应结合通电时间和变化趋势观察。"
                )
            }
            if snapshot.metrics.unsafeShutdowns != nil {
                KeyValueRow(
                    title: "非预期掉电计数",
                    value: SmartFormatting.integer(snapshot.metrics.unsafeShutdowns),
                    helpTitle: "非预期掉电计数",
                    help: "设备未收到正常关机通知便失去供电的累计次数，例如强制关机、突然断电或系统崩溃。偶发不等于硬盘损坏；持续增加时应检查供电和异常关机原因。"
                )
            }
            if snapshot.metrics.controllerBusyTime != nil {
                KeyValueRow(
                    title: "控制器忙碌时间",
                    value: L10n.f("%@ 分钟", SmartFormatting.integer(snapshot.metrics.controllerBusyTime)),
                    helpTitle: "控制器忙碌时间",
                    help: "NVMe 控制器处理 I/O 命令的累计忙碌时间，单位为分钟。它反映长期工作负载，不是本次任务耗时；0 也可能表示累计不足 1 分钟或设备未提供有效记录。"
                )
            }
        }
    }

    private var reliabilityCard: some View {
        DetailCard(title: "错误与可靠性", systemImage: "checkmark.shield") {
            if snapshot.metrics.mediaErrors != nil {
                KeyValueRow(
                    title: "介质与数据完整性错误",
                    value: SmartFormatting.integer(snapshot.metrics.mediaErrors),
                    helpTitle: "介质与数据完整性错误",
                    help: "NVMe 控制器检测到且未能恢复的数据完整性错误累计数，例如不可校正 ECC、CRC 校验失败或 LBA 标签不匹配。0 是理想状态；非 0 或持续增加时应及时备份并进一步检查。"
                )
            }
            if snapshot.metrics.errorLogEntries != nil {
                KeyValueRow(
                    title: "错误日志条目",
                    value: SmartFormatting.integer(snapshot.metrics.errorLogEntries),
                    helpTitle: "错误日志条目",
                    help: "控制器错误信息日志条目的累计数，可能包含可恢复或历史错误，不等同于介质损坏。应结合错误类型、介质错误计数和变化趋势判断；附加日志不可读时只能看到累计数，无法查看明细。"
                )
            }
            if snapshot.metrics.reportedUncorrectableErrors != nil {
                KeyValueRow(title: "报告的不可校正错误", value: SmartFormatting.integer(snapshot.metrics.reportedUncorrectableErrors))
            }
            if snapshot.metrics.commandTimeoutCount != nil {
                KeyValueRow(title: "命令超时", value: SmartFormatting.integer(snapshot.metrics.commandTimeoutCount))
            }
            if snapshot.metrics.endToEndErrorCount != nil {
                KeyValueRow(title: "端到端错误", value: SmartFormatting.integer(snapshot.metrics.endToEndErrorCount))
            }
            if snapshot.metrics.scsiNonMediumErrorCount != nil {
                KeyValueRow(title: "SCSI 非介质错误", value: SmartFormatting.integer(snapshot.metrics.scsiNonMediumErrorCount))
            }
            KeyValueRow(
                title: "读取完整性",
                value: snapshot.displayReadCompleteness.rawValue,
                helpTitle: "Read Completeness",
                help: "本 App 对 smartctl 读取结果的分层判断。核心健康字段可用时，即使附加错误日志明细无法读取，也不直接等同于硬盘故障。"
            )
        }
    }

    private var ataAttributesCard: some View {
        DetailCard(title: "ATA 扇区与接口状态", systemImage: "externaldrive.badge.checkmark") {
            KeyValueRow(title: "已重映射扇区", value: SmartFormatting.integer(snapshot.metrics.reallocatedSectorCount))
            KeyValueRow(title: "重映射事件", value: SmartFormatting.integer(snapshot.metrics.reallocationEventCount))
            KeyValueRow(title: "当前待处理扇区", value: SmartFormatting.integer(snapshot.metrics.currentPendingSectorCount))
            KeyValueRow(title: "离线不可校正扇区", value: SmartFormatting.integer(snapshot.metrics.offlineUncorrectableSectorCount))
            KeyValueRow(title: "接口 CRC 错误", value: SmartFormatting.integer(snapshot.metrics.crcErrorCount))

            if let attributes = snapshot.ataAttributes, !attributes.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(attributes) { attribute in
                            KeyValueRow(
                                title: String(format: "%03d %@", attribute.id, attribute.name),
                                value: ataAttributeValue(attribute),
                                monospaced: true
                            )
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(L10n.f("完整 ATA SMART 属性表（%d 项）", attributes.count))
                }
            }
        }
    }

    private var scsiErrorCard: some View {
        DetailCard(title: "SCSI 错误计数", systemImage: "list.number") {
            scsiCounterRows(title: "读取", counter: snapshot.scsiErrorCounters?.read)
            scsiCounterRows(title: "写入", counter: snapshot.scsiErrorCounters?.write)
            scsiCounterRows(title: "校验", counter: snapshot.scsiErrorCounters?.verify)
            KeyValueRow(title: "增长缺陷列表", value: SmartFormatting.integer(snapshot.metrics.scsiGrownDefectList))
            KeyValueRow(title: "非介质错误", value: SmartFormatting.integer(snapshot.metrics.scsiNonMediumErrorCount))
        }
    }

    @ViewBuilder
    private func scsiCounterRows(title: String, counter: SCSIErrorCounter?) -> some View {
        if let counter {
            KeyValueRow(title: L10n.f("%@已校正错误", L10n.t(title)), value: SmartFormatting.integer(counter.totalCorrected))
            KeyValueRow(title: L10n.f("%@不可校正错误", L10n.t(title)), value: SmartFormatting.integer(counter.totalUncorrected))
            if let gigabytes = counter.gigabytesProcessed {
                KeyValueRow(title: L10n.f("%@处理量", L10n.t(title)), value: String(format: "%.3f GB", gigabytes))
            }
        }
    }

    private var hasNVMeReadWriteStatistics: Bool {
        snapshot.metrics.dataUnitsRead != nil || snapshot.metrics.dataUnitsWritten != nil ||
            snapshot.metrics.hostReads != nil || snapshot.metrics.hostWrites != nil
    }

    private func ataAttributeValue(_ attribute: ATASmartAttribute) -> String {
        var parts: [String] = []
        if let current = attribute.currentValue { parts.append("Value \(current)") }
        if let worst = attribute.worstValue { parts.append("Worst \(worst)") }
        if let threshold = attribute.threshold { parts.append("Threshold \(threshold)") }
        if let raw = attribute.rawString ?? attribute.rawValue.map(String.init) { parts.append("Raw \(raw)") }
        if attribute.hasFailed { parts.append(L10n.t("已触发阈值")) }
        return parts.isEmpty ? L10n.t("未返回") : parts.joined(separator: " · ")
    }

    private var serialText: String {
        guard let serial = snapshot.device.serialNumber, !serial.isEmpty else { return L10n.t("未返回") }
        return showSerial ? serial : L10n.t("已隐藏")
    }
}

struct DetailCard<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, systemImage: systemImage)
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .labGlassCard()
    }
}

struct DiagnosticCard: View {
    var snapshot: SmartSnapshot

    var body: some View {
        DetailCard(title: "读取诊断", systemImage: "stethoscope") {
            KeyValueRow(
                title: "读取方式",
                value: snapshot.readMode.rawValue,
                helpTitle: "Read Source",
                help: "本次读取 smartctl 的来源。正式 App 优先使用包内 smartctl；手动路径只作为普通 direct fallback，不会作为 root helper 的任意执行路径。"
            )
            CopyablePathRow(
                title: "smartctl",
                value: snapshot.smartctlPath ?? "未返回",
                helpTitle: "smartctl Path",
                help: "本次实际执行的 smartctl 路径。路径用于诊断和复核来源；App 不会执行除 smartctl 固定只读参数以外的任意命令。"
            )
            KeyValueRow(
                title: "版本",
                value: snapshot.smartctlVersion ?? "未返回",
                helpTitle: "smartctl Version",
                help: "smartmontools / smartctl 的版本。不同版本对 NVMe、ATA/SATA、SCSI 字段和 JSON 输出的支持可能略有差异。"
            )
            KeyValueRow(
                title: "读取完整性",
                value: snapshot.displayReadCompleteness.rawValue,
                helpTitle: "Read Completeness",
                help: "区分硬盘健康和读取范围。本 App 会优先确保当前协议的核心 SMART 字段可用，再把附加日志失败放入诊断层。"
            )

            ForEach(snapshot.displayReadCompletenessReasons, id: \.self) { reason in
                Label(L10n.t(reason), systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }

            if let diagnostics = snapshot.smartctlDiagnostics, !diagnostics.isEmpty {
                ForEach(diagnostics) { diagnostic in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            KeyValueRow(
                                title: "命令",
                                value: diagnostic.arguments.joined(separator: " "),
                                monospaced: true,
                                helpTitle: "Command",
                                help: "诊断中展示的只读命令。代码层只允许固定 smartctl 参数读取枚举到的 whole-disk /dev/diskN，不允许 shell、格式化、修复、挂载或写盘类命令。"
                            )
                            KeyValueRow(
                                title: "Exit Status",
                                value: diagnostic.exitStatus.map(String.init) ?? "未返回",
                                helpTitle: "smartctl Exit Status",
                                help: "smartctl 的退出状态。非 0 不一定代表硬盘故障；例如附加错误日志明细读取失败可能返回 Exit 4，但核心健康字段仍然可用。"
                            )
                            if !diagnostic.messages.isEmpty {
                                ForEach(diagnostic.messages) { message in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(message.severity.uppercased())
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Text(message.message)
                                            .font(.callout)
                                            .foregroundStyle(.primary)
                                            .textSelection(.enabled)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            if let stderr = diagnostic.stderrText, !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(stderr)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack {
                            Text(L10n.t(diagnostic.title))
                            Spacer()
                            Text(L10n.f("Exit %@", diagnostic.exitStatus.map(String.init) ?? L10n.t("未返回")))
                                .foregroundStyle(.secondary)
                                .font(.caption.monospacedDigit())
                        }
                    }
                    .padding(.top, 6)
                }
            } else if !snapshot.smartctlMessages.isEmpty || snapshot.smartctlExitStatus != nil {
                DisclosureGroup {
                    KeyValueRow(title: "Exit Status", value: snapshot.smartctlExitStatus.map(String.init) ?? "未返回")
                    ForEach(snapshot.smartctlMessages) { message in
                        Text(message.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } label: {
                    Text("旧版读取诊断")
                }
                .padding(.top, 6)
            }
        }
    }
}

struct RawJSONCard: View {
    var snapshot: SmartSnapshot
    @State private var expanded = false
    @State private var showSensitiveValues = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        L10n.t(showSensitiveValues ? "正在显示完整设备标识" : "序列号等设备标识已隐藏"),
                        systemImage: showSensitiveValues ? "eye" : "eye.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(showSensitiveValues ? .orange : .secondary)
                    Spacer()
                    Button {
                        showSensitiveValues.toggle()
                    } label: {
                        Label(
                            L10n.t(showSensitiveValues ? "隐藏完整标识" : "显示完整标识"),
                            systemImage: showSensitiveValues ? "eye.slash" : "eye"
                        )
                    }
                }
                ScrollView([.horizontal, .vertical]) {
                    Text(showSensitiveValues ? snapshot.rawJSON : SmartPrivacyRedactor.redactJSON(snapshot.rawJSON))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }
                .frame(maxHeight: 360)
            }
        } label: {
            SectionHeader(title: "全部原始参数", systemImage: "curlybraces")
        }
        .labGlassCard()
    }
}

struct FailureView: View {
    var failure: SmartctlFailure
    @State private var showSensitiveValues = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.t(failure.title), systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
            Text(L10n.t(failure.message))
                .font(.body)
            Text(L10n.t(failure.recovery))
                .font(.callout)
                .foregroundStyle(.secondary)
            if !failure.checkedPaths.isEmpty {
                Text(L10n.t("已检查路径"))
                    .font(.headline)
                    .padding(.top, 4)
                ForEach(failure.checkedPaths, id: \.self) { path in
                    Text(SmartPrivacyRedactor.privacySafeDisplayPath(path))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            if let preview = failure.rawOutputPreview, !preview.isEmpty {
                HStack {
                    Label(
                        L10n.t(showSensitiveValues ? "正在显示完整设备标识" : "序列号等设备标识已隐藏"),
                        systemImage: showSensitiveValues ? "eye" : "eye.slash"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(showSensitiveValues ? .orange : .secondary)
                    Spacer()
                    Button {
                        showSensitiveValues.toggle()
                    } label: {
                        Label(
                            L10n.t(showSensitiveValues ? "隐藏完整标识" : "显示完整标识"),
                            systemImage: showSensitiveValues ? "eye.slash" : "eye"
                        )
                    }
                }
                Text(showSensitiveValues ? preview : SmartPrivacyRedactor.redactJSON(preview))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 6)
            }
        }
        .labGlassCard()
    }
}

struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView(
            "等待生成当前硬盘健康报告",
            systemImage: "externaldrive.connected.to.line.below",
            description: Text("选择硬盘目标后会自动检测，也可以点击立即检测。")
        )
        .frame(maxWidth: .infinity, minHeight: 240)
        .labGlassCard(padding: 24)
    }
}
