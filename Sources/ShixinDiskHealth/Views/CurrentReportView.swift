import ShixinDiskHealthCore
import SwiftUI

struct CurrentReportView: View {
    @EnvironmentObject private var appState: DiskHealthAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ReportToolbarHeader()

                if let failure = appState.lastFailure {
                    FailureView(failure: failure)
                }

                if let snapshot = appState.currentSnapshotForSelectedDisk {
                    HealthOverviewCard(snapshot: snapshot)
                    CoreMetricGrid(snapshot: snapshot)
                    if let delta = appState.currentDelta {
                        DeltaCard(delta: delta)
                    }
                    DetailSectionsView(snapshot: snapshot, showSerial: appState.showSerialNumber)
                    RawJSONCard(snapshot: snapshot)
                } else if appState.lastFailure == nil {
                    EmptyStateView()
                }
            }
            .padding(22)
        }
    }
}

struct ReportToolbarHeader: View {
    @EnvironmentObject private var appState: DiskHealthAppState
    @State private var isCheckAnimationActive = false
    @State private var checkRotation: Double = 0
    @State private var showSavedPopover = false
    @State private var savedPopoverToken = UUID()

    var body: some View {
        ViewThatFits(in: .horizontal) {
            roomyHeader
                .frame(minWidth: 980)
            balancedHorizontalHeader
                .frame(minWidth: 680)
            compactHeader
        }
        .labGlassCard(padding: 16, cornerRadius: 18)
    }

    private var roomyHeader: some View {
        HStack(spacing: 22) {
            titleBlock
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(3)
            deviceBlock
                .frame(width: 300, alignment: .trailing)
                .padding(.trailing, 6)
                .layoutPriority(2)
            actionButtons(controlSize: .large)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var balancedHorizontalHeader: some View {
        HStack(spacing: 6) {
            titleBlock
                .frame(width: 210, alignment: .leading)
                .layoutPriority(3)
            Spacer(minLength: 0)
            trailingStatusAndActions(controlSize: .regular, deviceWidth: 190, spacing: 10)
                .layoutPriority(4)
        }
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            titleBlock
            HStack(alignment: .center) {
                Spacer(minLength: 0)
                trailingStatusAndActions(controlSize: .regular, deviceWidth: 210)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: "SHIXIN LAB · 「存迹」")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .layoutPriority(10)
            Text("MacDisk Health · SMART / NVMe")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.88)
        }
    }

    private var deviceBlock: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(appState.currentSnapshotForSelectedDisk?.device.modelName ?? appState.selectedDiskTarget?.displayName ?? L10n.t("等待检测内置 SSD"))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(lastDetectionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 190, alignment: .trailing)
    }

    private func trailingStatusAndActions(controlSize: ControlSize, deviceWidth: CGFloat, spacing: CGFloat = 12) -> some View {
        HStack(spacing: spacing) {
            deviceBlock
                .frame(width: deviceWidth, alignment: .trailing)
            actionButtons(controlSize: controlSize)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func actionButtons(controlSize: ControlSize) -> some View {
        HStack(spacing: 8) {
            Button {
                if appState.isDetectingInternalDisk {
                    appState.cancelDetection()
                } else if !appState.isDetecting {
                    runAnimatedDetection()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: appState.isDetectingInternalDisk ? "stop.circle.fill" : "arrow.clockwise")
                        .rotationEffect(.degrees(checkRotation))
                    Text(L10n.t(appState.isDetectingInternalDisk ? "停止检测" : (isCheckAnimationActive ? "检测中" : "立即检测")))
                }
                .frame(minHeight: 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(controlSize)
            .disabled(
                (!appState.isDetecting && isCheckAnimationActive) ||
                    (!appState.isDetecting && appState.selectedDiskTarget?.canReadSMART != true) ||
                    (appState.isDetecting && !appState.isDetectingInternalDisk)
            )

            Button {
                if appState.saveCurrentSnapshot() {
                    showSnapshotSavedPopover()
                }
            } label: {
                Label("保存快照", systemImage: "square.and.arrow.down")
                    .frame(minHeight: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(controlSize)
            .disabled(!appState.canSaveCurrentSnapshot)
            .popover(isPresented: $showSavedPopover, arrowEdge: .top) {
                snapshotSavedPopover
            }
        }
    }

    private var snapshotSavedPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("快照已保存"))
                .font(.headline)
            Text(L10n.t("已写入本机历史记录，可在历史记录中回看。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }

    private func runAnimatedDetection() {
        guard !appState.isDetecting && !isCheckAnimationActive else { return }
        isCheckAnimationActive = true
        checkRotation = 0

        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
            checkRotation = 360
        }

        Task { @MainActor in
            await appState.runDetection()
            withAnimation(.easeOut(duration: 0.18)) {
                isCheckAnimationActive = false
                checkRotation = 0
            }
        }
    }

    private func showSnapshotSavedPopover() {
        let token = UUID()
        savedPopoverToken = token
        withAnimation(.easeOut(duration: 0.18)) {
            showSavedPopover = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard savedPopoverToken == token else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                showSavedPopover = false
            }
        }
    }

    private var lastDetectionText: String {
        guard let snapshot = appState.currentSnapshotForSelectedDisk else { return L10n.t("最近检测：未检测") }
        return L10n.f("最近检测：%@", SmartFormatting.shortDateTime(snapshot.capturedAt))
    }
}

struct DiskTargetSummary: View {
    var target: DiskTarget

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                summaryPills
                Spacer()
                detailText
                    .frame(maxWidth: 520, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 10) {
                summaryPills
                detailText
            }
        }
    }

    private var summaryPills: some View {
        HStack(spacing: 8) {
            StatusPill(text: L10n.t(target.connectionKind.shortTitle), systemImage: target.connectionKind.symbolName, tint: target.connectionKind.tint)
            StatusPill(
                text: L10n.t(target.smartSupportStatus.rawValue),
                systemImage: target.canReadSMART ? "checkmark.seal.fill" : "info.circle.fill",
                tint: target.canReadSMART ? .blue : .orange
            )
            if let path = target.devicePath {
                StatusPill(text: path, systemImage: "terminal", tint: .gray)
            }
        }
    }

    private var detailText: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(target.detailName ?? target.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            if let size = target.mediaSizeBytes ?? target.volumeCapacityBytes {
                Text(SmartFormatting.sizeString(size))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct HealthOverviewCard: View {
    var snapshot: SmartSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: snapshot.healthLevel.symbolName)
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(snapshot.healthLevel.accentColor)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(L10n.t(snapshot.healthLevel.title))
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(snapshot.healthLevel.accentColor)
                            .lineLimit(1)
                        StatusPill(
                            text: snapshot.displayReadCompleteness.rawValue,
                            systemImage: snapshot.displayReadCompleteness.symbolName,
                            tint: snapshot.displayReadCompleteness.accentColor
                        )
                    }
                    Text(L10n.t(snapshot.healthLevel.shortDescription))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 6) {
                        if let kind = snapshot.diskConnectionKind {
                            StatusPill(text: L10n.t(kind.shortTitle), systemImage: kind.symbolName, tint: kind.tint)
                        }
                        StatusPill(
                            text: snapshot.device.protocolName ?? snapshot.metrics.effectiveProtocolFamily.rawValue,
                            systemImage: "cable.connector",
                            tint: .gray
                        )
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    if snapshot.displayReadCompleteness == .coreCompleteSupplementalUnavailable {
                        StatusPill(
                            text: "附加日志未完整读取",
                            systemImage: "info.circle.fill",
                            tint: .blue
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }

            Divider().opacity(0.25)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.healthReasons, id: \.self) { reason in
                    Label(L10n.t(reason), systemImage: healthReasonSymbol)
                        .font(.callout)
                        .foregroundStyle(snapshot.healthLevel == .healthy ? Color.secondary : snapshot.healthLevel.accentColor)
                }
                ForEach(snapshot.displayReadCompletenessReasons, id: \.self) { reason in
                    Label(L10n.t(reason), systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .labGlassCard(padding: 18, cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    private var healthReasonSymbol: String {
        switch snapshot.healthLevel {
        case .healthy: "checkmark.circle"
        case .attention: "exclamationmark.triangle"
        case .risk: "xmark.octagon"
        case .unknown: "questionmark.circle"
        }
    }
}

struct CoreMetricGrid: View {
    var snapshot: SmartSnapshot

    var body: some View {
        ViewThatFits(in: .horizontal) {
            metricGrid(columnCount: 6, minimumWidth: 168)
            metricGrid(columnCount: 3, minimumWidth: 190)
            metricGrid(columnCount: 2, minimumWidth: 190)
        }
    }

    private func metricGrid(columnCount: Int, minimumWidth: CGFloat) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: minimumWidth, maximum: .infinity), spacing: 12, alignment: .top),
                count: columnCount
            ),
            spacing: 12
        ) {
            metricTiles
        }
    }

    @ViewBuilder
    private var metricTiles: some View {
        smartStatusTile
        switch snapshot.metrics.effectiveProtocolFamily {
        case .nvme:
            MetricTile(
                title: "寿命消耗",
                value: SmartFormatting.percent(snapshot.metrics.percentageUsed),
                detail: "Percentage Used",
                systemImage: "gauge.with.dots.needle.67percent",
                tint: snapshot.healthLevel.accentColor,
                help: "寿命消耗说明",
                usesProminentTitle: true
            )
            MetricTile(
                title: "当前温度",
                value: SmartFormatting.celsius(snapshot.metrics.temperatureCelsius),
                detail: "NVMe SMART Temperature",
                systemImage: "thermometer.medium",
                tint: .cyan,
                help: "当前温度说明",
                usesProminentTitle: true
            )
            MetricTile(
                title: "累计写入量",
                value: SmartFormatting.byteString(snapshot.metrics.writtenBytes),
                detail: "Data Units Written",
                systemImage: "square.and.arrow.down.fill",
                tint: .purple,
                help: "累计写入量说明",
                usesProminentTitle: true
            )
            MetricTile(
                title: "累计读取量",
                value: SmartFormatting.byteString(snapshot.metrics.readBytes),
                detail: "Data Units Read",
                systemImage: "square.and.arrow.up.fill",
                tint: .blue,
                help: "累计读取量说明",
                usesProminentTitle: true
            )
            MetricTile(
                title: "SSD 控制器通电小时",
                value: SmartFormatting.integer(snapshot.metrics.powerOnHours),
                detail: "Power On Hours",
                systemImage: "power.circle.fill",
                tint: .orange,
                help: "SSD 控制器通电小时说明",
                usesProminentTitle: true
            )
        case .ata:
            MetricTile(
                title: "当前待处理扇区",
                value: SmartFormatting.integer(snapshot.metrics.currentPendingSectorCount),
                detail: "Current Pending Sector",
                systemImage: "exclamationmark.circle.fill",
                tint: countTint(snapshot.metrics.currentPendingSectorCount, risk: true),
                usesProminentTitle: true
            )
            MetricTile(
                title: "离线不可校正扇区",
                value: SmartFormatting.integer(snapshot.metrics.offlineUncorrectableSectorCount),
                detail: "Offline Uncorrectable",
                systemImage: "xmark.octagon.fill",
                tint: countTint(snapshot.metrics.offlineUncorrectableSectorCount, risk: true),
                usesProminentTitle: true
            )
            MetricTile(
                title: "已重映射扇区",
                value: SmartFormatting.integer(snapshot.metrics.reallocatedSectorCount),
                detail: "Reallocated Sector Count",
                systemImage: "arrow.triangle.swap",
                tint: countTint(snapshot.metrics.reallocatedSectorCount, risk: false),
                usesProminentTitle: true
            )
            MetricTile(
                title: "接口 CRC 错误",
                value: SmartFormatting.integer(snapshot.metrics.crcErrorCount),
                detail: "UDMA CRC Error Count",
                systemImage: "cable.connector",
                tint: countTint(snapshot.metrics.crcErrorCount, risk: false),
                usesProminentTitle: true
            )
            temperatureTile
        case .scsi:
            MetricTile(
                title: "读取不可校正错误",
                value: SmartFormatting.integer(snapshot.metrics.scsiReadUncorrectedErrors),
                detail: "SCSI Read Uncorrected",
                systemImage: "arrow.up.circle.fill",
                tint: countTint(snapshot.metrics.scsiReadUncorrectedErrors, risk: true),
                usesProminentTitle: true
            )
            MetricTile(
                title: "写入不可校正错误",
                value: SmartFormatting.integer(snapshot.metrics.scsiWriteUncorrectedErrors),
                detail: "SCSI Write Uncorrected",
                systemImage: "arrow.down.circle.fill",
                tint: countTint(snapshot.metrics.scsiWriteUncorrectedErrors, risk: true),
                usesProminentTitle: true
            )
            MetricTile(
                title: "校验不可校正错误",
                value: SmartFormatting.integer(snapshot.metrics.scsiVerifyUncorrectedErrors),
                detail: "SCSI Verify Uncorrected",
                systemImage: "checkmark.circle.badge.questionmark",
                tint: countTint(snapshot.metrics.scsiVerifyUncorrectedErrors, risk: true),
                usesProminentTitle: true
            )
            MetricTile(
                title: "增长缺陷列表",
                value: SmartFormatting.integer(snapshot.metrics.scsiGrownDefectList),
                detail: "Grown Defect List",
                systemImage: "list.bullet.rectangle",
                tint: countTint(snapshot.metrics.scsiGrownDefectList, risk: false),
                usesProminentTitle: true
            )
            temperatureTile
        case .unknown:
            temperatureTile
            MetricTile(
                title: "通电小时",
                value: SmartFormatting.integer(snapshot.metrics.powerOnHours),
                detail: "Power On Hours",
                systemImage: "power.circle.fill",
                tint: .orange,
                usesProminentTitle: true
            )
        }
    }

    private var smartStatusTile: some View {
        MetricTile(
            title: "SMART 状态",
            value: snapshot.metrics.smartPassed == true ? "通过" : (snapshot.metrics.smartPassed == false ? "未通过" : "未返回"),
            detail: "整体健康判定",
            systemImage: snapshot.metrics.smartPassed == nil ? "questionmark.shield.fill" : "checkmark.shield.fill",
            tint: snapshot.metrics.smartPassed == true ? .green : (snapshot.metrics.smartPassed == false ? .red : .gray),
            help: "SMART 状态说明",
            usesProminentTitle: true
        )
    }

    private var temperatureTile: some View {
        MetricTile(
            title: "当前温度",
            value: SmartFormatting.celsius(snapshot.metrics.temperatureCelsius),
            detail: "SMART Temperature",
            systemImage: "thermometer.medium",
            tint: snapshot.metrics.temperatureCelsius == nil ? .gray : .cyan,
            help: "当前温度说明",
            usesProminentTitle: true
        )
    }

    private func countTint(_ value: Int64?, risk: Bool) -> Color {
        guard let value else { return .gray }
        guard value > 0 else { return .green }
        return risk ? .red : .orange
    }
}

struct DeltaCard: View {
    var delta: SnapshotDelta

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "较上次保存快照", systemImage: "chart.line.uptrend.xyaxis")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 10)], spacing: 10) {
                DeltaItem(title: "通电小时", value: L10n.f("%@ 小时", SmartFormatting.signedInteger(delta.powerOnHours)), help: "快照通电变化说明")
                DeltaItem(title: "电源循环次数", value: SmartFormatting.signedInteger(delta.powerCycles), help: "快照电源循环变化说明")
                switch delta.protocolFamily {
                case .nvme:
                    DeltaItem(title: "读取", value: SmartFormatting.signedByteString(delta.readBytes), help: "快照读取变化说明")
                    DeltaItem(title: "写入", value: SmartFormatting.signedByteString(delta.writtenBytes), help: "快照写入变化说明")
                    DeltaItem(title: "非预期掉电", value: SmartFormatting.signedInteger(delta.unsafeShutdowns), help: "快照非预期掉电变化说明")
                    DeltaItem(title: "介质错误", value: SmartFormatting.signedInteger(delta.mediaErrors), help: "快照介质错误变化说明")
                    DeltaItem(title: "错误日志", value: SmartFormatting.signedInteger(delta.errorLogEntries), help: "快照错误日志变化说明")
                    DeltaItem(title: "寿命消耗", value: "\(SmartFormatting.signedInteger(delta.percentageUsed))%", help: "快照寿命消耗变化说明")
                case .ata:
                    DeltaItem(title: "已重映射扇区", value: SmartFormatting.signedInteger(delta.reallocatedSectorCount))
                    DeltaItem(title: "当前待处理扇区", value: SmartFormatting.signedInteger(delta.currentPendingSectorCount))
                    DeltaItem(title: "离线不可校正扇区", value: SmartFormatting.signedInteger(delta.offlineUncorrectableSectorCount))
                    DeltaItem(title: "接口 CRC 错误", value: SmartFormatting.signedInteger(delta.crcErrorCount))
                case .scsi:
                    DeltaItem(title: "读取不可校正错误", value: SmartFormatting.signedInteger(delta.scsiReadUncorrectedErrors))
                    DeltaItem(title: "写入不可校正错误", value: SmartFormatting.signedInteger(delta.scsiWriteUncorrectedErrors))
                    DeltaItem(title: "校验不可校正错误", value: SmartFormatting.signedInteger(delta.scsiVerifyUncorrectedErrors))
                case .unknown:
                    EmptyView()
                }
            }
        }
        .labGlassCard()
    }
}

struct DeltaItem: View {
    var title: String
    var value: String
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
            HStack(spacing: 4) {
                Text(L10n.t(title))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                if let help, !help.isEmpty {
                    InfoHelpButton(title: title, message: help)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
