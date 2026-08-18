import Charts
import ShixinDiskHealthCore
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: DiskHealthAppState

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width < 900 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        historyList
                        historyDetail
                    }
                    .padding(22)
                }
            } else {
                HStack(spacing: 0) {
                    historyList
                        .frame(width: min(390, max(330, proxy.size.width * 0.32)))
                        .padding(18)
                        .background(.ultraThinMaterial)

                    Divider().opacity(0.25)

                    ScrollView {
                        historyDetail
                            .padding(22)
                    }
                }
            }
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 14) {
            historyHeader

            if appState.snapshotsForSelectedHistoryGroup.isEmpty {
                ContentUnavailableView(
                    "还没有保存的快照",
                    systemImage: "clock.badge.questionmark",
                    description: Text("保存当前硬盘目标的快照后，这里会显示可回顾的历史记录。")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                List(appState.snapshotsForSelectedHistoryGroup, selection: $appState.selectedSnapshotID) { snapshot in
                    SnapshotListRow(snapshot: snapshot)
                        .tag(snapshot.id)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 280)
            }
        }
    }

    private var historyHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                historyTitle
                if !appState.historyGroups.isEmpty {
                    historyPicker
                        .frame(width: 210, alignment: .leading)
                }
                Spacer(minLength: 10)
                headerStatusCluster
                exportMenu
            }
            .frame(minWidth: 650)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    historyTitle
                    Spacer(minLength: 0)
                    exportMenu
                }
                if !appState.historyGroups.isEmpty {
                    HStack(spacing: 10) {
                        historyPicker
                        Spacer(minLength: 0)
                        headerStatusCluster
                    }
                }
            }
        }
    }

    private var historyTitle: some View {
        Text("历史记录")
            .font(.title2.weight(.semibold))
            .fixedSize(horizontal: true, vertical: false)
    }

    private var exportMenu: some View {
        Menu {
            Button("导出 JSON") { appState.exportSnapshots(format: .json) }
            Button("导出 CSV") { appState.exportSnapshots(format: .csv) }
        } label: {
            Label("导出", systemImage: "square.and.arrow.up")
        }
        .controlSize(.regular)
        .frame(height: 32)
        .disabled(appState.snapshotsForSelectedHistoryGroup.isEmpty)
    }

    private var historyPicker: some View {
        Picker("历史硬盘", selection: historySelection) {
            ForEach(appState.historyGroups) { group in
                HStack {
                    Text(group.displayName)
                    Text(group.isConnected ? L10n.t("已连接") : L10n.t("离线"))
                }
                .tag(Optional(group.identityRawValue))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityLabel(L10n.t("历史硬盘"))
    }

    private var headerStatusCluster: some View {
        HStack(spacing: 8) {
            selectedSnapshotCount
            selectedGroupPills
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var selectedSnapshotCount: some View {
        if let group = appState.selectedHistoryGroup {
            Text(L10n.f("%d 个快照", group.snapshots.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var selectedGroupPills: some View {
        if let group = appState.selectedHistoryGroup {
            HStack(spacing: 8) {
                StatusPill(
                    text: group.isConnected ? L10n.t("已连接") : L10n.t("离线硬盘"),
                    systemImage: group.isConnected ? "externaldrive.badge.checkmark" : "externaldrive.badge.xmark",
                    tint: group.isConnected ? .blue : .gray
                )
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 32)
                if let kind = group.connectionKind {
                    StatusPill(text: L10n.t(kind.shortTitle), systemImage: kind.symbolName, tint: kind.tint)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(height: 32)
                }
            }
        }
    }

    private var historySelection: Binding<String?> {
        Binding {
            appState.selectedHistoryIdentity
        } set: { newValue in
            appState.selectHistoryGroup(identityRawValue: newValue)
        }
    }

    @ViewBuilder
    private var historyDetail: some View {
        if let snapshot = appState.selectedSnapshot {
            VStack(alignment: .leading, spacing: 16) {
                if let failure = appState.historyFailure {
                    FailureView(failure: failure)
                }
                TrendChartView(snapshots: appState.snapshotsForSelectedHistoryGroup)
                HistorySnapshotDetail(snapshot: snapshot)
            }
        } else if let failure = appState.historyFailure {
            VStack(alignment: .leading, spacing: 16) {
                FailureView(failure: failure)
                emptyHistoryDetail
            }
        } else {
            emptyHistoryDetail
        }
    }

    private var emptyHistoryDetail: some View {
        ContentUnavailableView(
            "选择一个快照",
            systemImage: "doc.text.magnifyingglass",
            description: Text("保存或选择快照后可查看详情。")
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

struct SnapshotListRow: View {
    var snapshot: SmartSnapshot

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: snapshot.healthLevel.symbolName)
                .foregroundStyle(snapshot.healthLevel.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(SmartFormatting.shortDateTime(snapshot.capturedAt))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(snapshot.device.modelName ?? snapshot.device.deviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let diskName = snapshot.diskDisplayName {
                    Text(diskName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if snapshot.displayReadCompleteness == .coreCompleteSupplementalUnavailable {
                    Text(L10n.t("附加日志未完整读取"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

struct HistorySnapshotDetail: View {
    @EnvironmentObject private var appState: DiskHealthAppState
    var snapshot: SmartSnapshot
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("快照详情")
                        .font(.title2.weight(.semibold))
                    Text(SmartFormatting.shortDateTime(snapshot.capturedAt))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }

            HealthOverviewCard(snapshot: snapshot)
            CoreMetricGrid(snapshot: snapshot)
            DetailSectionsView(snapshot: snapshot, showSerial: appState.showSerialNumber)
        }
        .confirmationDialog("删除这个历史快照？", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) {
                appState.deleteSnapshot(snapshot)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只删除本机历史记录中的这个快照，不会修改磁盘。")
        }
    }
}

struct TrendChartView: View {
    var snapshots: [SmartSnapshot]

    private var ordered: [SmartSnapshot] {
        snapshots.sorted { $0.capturedAt < $1.capturedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "趋势图", systemImage: "chart.xyaxis.line")
            if ordered.count < 2 {
                ContentUnavailableView(
                    "需要至少两次快照",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("保存两次或更多快照后，会显示读取、写入、温度和寿命消耗趋势。")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart {
                    ForEach(ordered) { snapshot in
                        if let written = snapshot.metrics.writtenBytes {
                            LineMark(
                                x: .value(L10n.t("时间"), snapshot.capturedAt),
                                y: .value("TB", written / 1_000_000_000_000),
                                series: .value(L10n.t("指标"), L10n.t("累计写入 TB"))
                            )
                            .foregroundStyle(by: .value(L10n.t("指标"), L10n.t("累计写入 TB")))
                            .interpolationMethod(.linear)
                            .lineStyle(trendLineStyle)
                        }
                        if let read = snapshot.metrics.readBytes {
                            LineMark(
                                x: .value(L10n.t("时间"), snapshot.capturedAt),
                                y: .value("TB", read / 1_000_000_000_000),
                                series: .value(L10n.t("指标"), L10n.t("累计读取 TB"))
                            )
                            .foregroundStyle(by: .value(L10n.t("指标"), L10n.t("累计读取 TB")))
                            .interpolationMethod(.linear)
                            .lineStyle(trendLineStyle)
                        }
                    }
                }
                .chartLegend(position: .bottom)
                .frame(height: 220)

                Chart {
                    ForEach(ordered) { snapshot in
                        if let temperature = snapshot.metrics.temperatureCelsius {
                            LineMark(
                                x: .value(L10n.t("时间"), snapshot.capturedAt),
                                y: .value(L10n.t("温度"), temperature),
                                series: .value(L10n.t("指标"), L10n.t("温度 °C"))
                            )
                            .foregroundStyle(by: .value(L10n.t("指标"), L10n.t("温度 °C")))
                            .interpolationMethod(.linear)
                            .lineStyle(trendLineStyle)
                        }
                        if let used = snapshot.metrics.percentageUsed {
                            LineMark(
                                x: .value(L10n.t("时间"), snapshot.capturedAt),
                                y: .value(L10n.t("寿命消耗"), used),
                                series: .value(L10n.t("指标"), L10n.t("寿命消耗 %"))
                            )
                            .foregroundStyle(by: .value(L10n.t("指标"), L10n.t("寿命消耗 %")))
                            .interpolationMethod(.linear)
                            .lineStyle(trendLineStyle)
                        }
                        if let pending = snapshot.metrics.currentPendingSectorCount {
                            LineMark(
                                x: .value(L10n.t("时间"), snapshot.capturedAt),
                                y: .value(L10n.t("当前待处理扇区"), pending),
                                series: .value(L10n.t("指标"), L10n.t("当前待处理扇区"))
                            )
                            .foregroundStyle(by: .value(L10n.t("指标"), L10n.t("当前待处理扇区")))
                            .interpolationMethod(.linear)
                            .lineStyle(trendLineStyle)
                        }
                        if let reallocated = snapshot.metrics.reallocatedSectorCount {
                            LineMark(
                                x: .value(L10n.t("时间"), snapshot.capturedAt),
                                y: .value(L10n.t("已重映射扇区"), reallocated),
                                series: .value(L10n.t("指标"), L10n.t("已重映射扇区"))
                            )
                            .foregroundStyle(by: .value(L10n.t("指标"), L10n.t("已重映射扇区")))
                            .interpolationMethod(.linear)
                            .lineStyle(trendLineStyle)
                        }
                        let scsiUncorrected = [
                            snapshot.metrics.scsiReadUncorrectedErrors,
                            snapshot.metrics.scsiWriteUncorrectedErrors,
                            snapshot.metrics.scsiVerifyUncorrectedErrors
                        ].compactMap { $0 }.reduce(0, +)
                        if snapshot.metrics.effectiveProtocolFamily == .scsi {
                            LineMark(
                                x: .value(L10n.t("时间"), snapshot.capturedAt),
                                y: .value(L10n.t("SCSI 不可校正错误"), scsiUncorrected),
                                series: .value(L10n.t("指标"), L10n.t("SCSI 不可校正错误"))
                            )
                            .foregroundStyle(by: .value(L10n.t("指标"), L10n.t("SCSI 不可校正错误")))
                            .interpolationMethod(.linear)
                            .lineStyle(trendLineStyle)
                        }
                    }
                }
                .chartLegend(position: .bottom)
                .frame(height: 180)
            }
        }
        .labGlassCard()
    }

    private var trendLineStyle: StrokeStyle {
        StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
    }
}
