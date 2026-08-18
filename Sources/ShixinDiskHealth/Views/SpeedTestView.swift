import Charts
import ShixinDiskHealthCore
import SwiftUI

struct SpeedTestView: View {
    @EnvironmentObject private var speedState: SpeedTestAppState

    var body: some View {
        GeometryReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SpeedTestHeader()
                    SpeedTestSafetyCard()

                    if let failure = speedState.lastFailure {
                        SpeedTestFailureCard(failure: failure)
                    }
                    if let warning = speedState.lastCleanupWarning, !warning.isEmpty {
                        SpeedTestCleanupWarningCard(warning: warning)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SpeedTestControlCard()
                        SpeedTestLiveCard()
                    }

                    SpeedTestHistoryCard()
                }
                .padding(22)
            }
        }
    }
}

struct SpeedTestHeader: View {
    @EnvironmentObject private var speedState: SpeedTestAppState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                titleBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusBlock
                actionButton
            }

            VStack(alignment: .leading, spacing: 14) {
                titleBlock
                HStack {
                    statusBlock
                    Spacer()
                    actionButton
                }
            }
        }
        .labGlassCard(padding: 16, cornerRadius: 18)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("速度测试")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            Text("顺序写入 / 顺序读取文件测速")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(L10n.t(speedState.progress.phase.rawValue))
                .font(.headline)
                .lineLimit(1)
            if let latest = speedState.latestResult {
                Text(L10n.f("最近：写 %@ / 读 %@", SmartFormatting.speedMBps(latest.writeAverageMBps), SmartFormatting.speedMBps(latest.readAverageMBps)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                Text(L10n.t("最近：未测试"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if speedState.isRunning {
            Button {
                speedState.startOrStop()
            } label: {
                Label("停止", systemImage: "stop.circle.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            Button {
                speedState.startOrStop()
            } label: {
                Label("开始测试", systemImage: "play.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

struct SpeedTestSafetyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "安全边界", systemImage: "lock.shield")
            ViewThatFits(in: .horizontal) {
                safetyGrid(columns: [
                    GridItem(.flexible(minimum: 185), spacing: 18),
                    GridItem(.flexible(minimum: 185), spacing: 18),
                    GridItem(.flexible(minimum: 185), spacing: 18)
                ])
                safetyGrid(columns: [
                    GridItem(.flexible(minimum: 240), spacing: 18),
                    GridItem(.flexible(minimum: 240), spacing: 18)
                ])
                safetyGrid(columns: [GridItem(.flexible(minimum: 240), spacing: 12)])
            }
            Text("速度测试会产生真实存储写入量；默认 5 GB，测试完成后自动删除临时文件。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .labGlassCard()
    }

    private func safetyGrid(columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            safetyItem("普通文件读写", "只在测试目录创建临时文件", "doc.badge.gearshape")
            safetyItem("不写原始磁盘", "不会写入 /dev/disk0 或 /dev/*", "internaldrive")
            safetyItem("不执行命令", "不用 dd、shell、diskutil 或修复工具", "terminal")
            safetyItem("本地完成", "不联网，不上传测速结果", "network.slash")
            safetyItem("空间预检查", "开始前确认容量，并预留 1 GB 缓冲", "checkmark.circle")
            safetyItem("中断可清理", "停止、失败或启动只清理临时文件", "arrow.clockwise.circle")
        }
    }

    private func safetyItem(_ title: String, _ subtitle: String, _ image: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: image)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(title))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(L10n.t(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SpeedTestControlCard: View {
    @EnvironmentObject private var speedState: SpeedTestAppState
    @EnvironmentObject private var appState: DiskHealthAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "测试设置", systemImage: "slider.horizontal.3")

            sizeAndModeRow

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("目标目录")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    StatusPill(
                        text: speedState.currentTargetDisplayName,
                        systemImage: speedState.targetKind == .defaultCacheDirectory ? "folder.badge.gearshape" : "folder",
                        tint: speedState.targetKind == .defaultCacheDirectory ? .blue : .purple
                    )
                }
                Text("选择哪个目录，就测试该目录所在卷的普通文件读写速度。默认目录通常位于内置系统数据卷。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        speedState.useDefaultTargetDirectory()
                    } label: {
                        Label("默认临时目录", systemImage: "folder.badge.gearshape")
                    }
                    .disabled(speedState.isRunning)

                    Button {
                        speedState.chooseTargetDirectory()
                    } label: {
                        Label("选择文件夹", systemImage: "folder")
                    }
                    .disabled(speedState.isRunning)
                    if !appState.diskInventory.speedTestTargets.isEmpty {
                        Menu {
                            ForEach(appState.diskInventory.speedTestTargets) { target in
                                Button {
                                    speedState.useDiskTargetVolume(target)
                                } label: {
                                    Label(target.displayName, systemImage: target.connectionKind.symbolName)
                                }
                            }
                        } label: {
                            Label("选择已挂载卷", systemImage: "externaldrive.connected.to.line.below")
                        }
                        .disabled(speedState.isRunning)
                    }
                }
            }

            if speedState.isRunning {
                Button {
                    speedState.startOrStop()
                } label: {
                    Label("停止当前测试", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    speedState.startOrStop()
                } label: {
                    Label("开始测试", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .labGlassCard()
    }

    private var sizeAndModeRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 32) {
                sizePicker
                modePicker
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                sizePicker
                modePicker
            }
        }
    }

    private var sizePicker: some View {
        HStack(spacing: 10) {
            Text("测试大小")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Picker("测试大小", selection: $speedState.selectedSize) {
                ForEach(SpeedTestSizeOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .disabled(speedState.isRunning)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 10) {
            Text("模式")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Picker("模式", selection: $speedState.selectedMode) {
                ForEach(SpeedTestMode.allCases) { mode in
                    Text(L10n.t(mode.rawValue)).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .disabled(speedState.isRunning)
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct SpeedTestLiveCard: View {
    @EnvironmentObject private var speedState: SpeedTestAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "实时结果", systemImage: "speedometer")

            LazyVGrid(columns: [GridItem(.flexible(minimum: 180)), GridItem(.flexible(minimum: 180))], spacing: 12) {
                MetricTile(
                    title: "顺序写入",
                    value: writeSpeedText,
                    detail: "Average Write",
                    systemImage: "square.and.arrow.down.fill",
                    tint: .purple
                )
                MetricTile(
                    title: "顺序读取",
                    value: readSpeedText,
                    detail: "Average Read",
                    systemImage: "square.and.arrow.up.fill",
                    tint: .blue
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StatusPill(
                        text: speedState.progress.phase.rawValue,
                        systemImage: speedState.progress.phase.symbolName,
                        tint: phaseTint
                    )
                    Spacer()
                    Text(L10n.f("第 %d 轮", speedState.progress.cycleIndex))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: speedState.progress.progressFraction)
                HStack {
                    Text("\(SmartFormatting.sizeString(speedState.progress.bytesProcessed)) / \(SmartFormatting.sizeString(speedState.progress.testSizeBytes))")
                    Spacer()
                    Text("\(Int(speedState.progress.progressFraction * 100))%")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                SpeedSmallStat(title: "当前速度", value: SmartFormatting.speedMBps(speedState.progress.currentMBps))
                SpeedSmallStat(title: "阶段平均", value: SmartFormatting.speedMBps(speedState.progress.averageMBps))
                SpeedSmallStat(title: "阶段峰值", value: SmartFormatting.speedMBps(speedState.progress.peakMBps))
                SpeedSmallStat(title: "阶段耗时", value: SmartFormatting.seconds(speedState.progress.elapsedSeconds))
            }
        }
        .labGlassCard()
    }

    private var writeSpeedText: String {
        if speedState.isRunning, speedState.progress.phase == .writing {
            return SmartFormatting.speedMBps(speedState.progress.averageMBps)
        }
        return SmartFormatting.speedMBps(speedState.latestResult?.writeAverageMBps)
    }

    private var readSpeedText: String {
        if speedState.isRunning, speedState.progress.phase == .reading {
            return SmartFormatting.speedMBps(speedState.progress.averageMBps)
        }
        return SmartFormatting.speedMBps(speedState.latestResult?.readAverageMBps)
    }

    private var phaseTint: Color {
        switch speedState.progress.phase {
        case .completed: .green
        case .failed: .red
        case .cancelled: .orange
        case .idle: .gray
        default: .blue
        }
    }
}

struct SpeedSmallStat: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(L10n.t(title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SpeedTestHistoryCard: View {
    @EnvironmentObject private var speedState: SpeedTestAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeader(title: "测速历史与趋势", systemImage: "chart.xyaxis.line")
                Menu {
                    Button("导出 JSON") { speedState.exportResults(format: .json) }
                    Button("导出 CSV") { speedState.exportResults(format: .csv) }
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .disabled(speedState.resultsForSelectedTarget.isEmpty)
            }

            if !speedState.historyGroups.isEmpty {
                Picker("测速目标", selection: historySelection) {
                    ForEach(speedState.historyGroups) { group in
                        Label(group.displayName, systemImage: group.connectionKind?.symbolName ?? "folder")
                            .tag(Optional(group.key))
                    }
                }
                .pickerStyle(.menu)
            }

            SpeedTestTrendChart(results: speedState.resultsForSelectedTarget)

            if speedState.resultsForSelectedTarget.isEmpty {
                ContentUnavailableView(
                    "还没有测速历史",
                    systemImage: "speedometer",
                    description: Text("完成一次速度测试后，这里会显示历史记录和趋势图。")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        SpeedResultList()
                            .frame(width: 360)
                        SpeedResultDetail()
                            .frame(maxWidth: .infinity, alignment: .top)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SpeedResultList()
                        SpeedResultDetail()
                    }
                }
            }
        }
        .labGlassCard()
    }

    private var historySelection: Binding<String?> {
        Binding {
            speedState.selectedHistoryGroupKey
        } set: { key in
            speedState.selectHistoryGroup(key: key)
        }
    }
}

struct SpeedTestTrendChart: View {
    var results: [SpeedTestResult]

    private var ordered: [SpeedTestResult] {
        results.sorted { $0.completedAt < $1.completedAt }
    }

    // Historical tests often arrive in tight bursts separated by weeks. Using
    // wall-clock time as the horizontal scale collapses a burst into a vertical
    // spike. Give every saved test one equal-width position instead; the axis
    // still shows its real date and time.
    private var axisIndices: [Int] {
        let count = ordered.count
        guard count > 1 else { return count == 1 ? [0] : [] }
        let tickCount = min(5, count)
        return (0..<tickCount).reduce(into: [Int]()) { indices, tick in
            let index = Int(
                (Double(tick) * Double(count - 1) / Double(tickCount - 1)).rounded()
            )
            if indices.last != index {
                indices.append(index)
            }
        }
    }

    var body: some View {
        if ordered.count < 2 {
            ContentUnavailableView(
                "需要至少两次测速",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("保存两次或更多测速结果后，会显示顺序写入和顺序读取趋势。")
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            Chart {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, result in
                    LineMark(
                        x: .value(L10n.t("测试顺序"), index),
                        y: .value("MB/s", result.writeAverageMBps),
                        series: .value(L10n.t("指标"), L10n.t("写入平均"))
                    )
                    .foregroundStyle(by: .value(L10n.t("指标"), L10n.t("写入平均")))
                    .interpolationMethod(.linear)

                    PointMark(
                        x: .value(L10n.t("测试顺序"), index),
                        y: .value("MB/s", result.writeAverageMBps)
                    )
                    .foregroundStyle(by: .value(L10n.t("指标"), L10n.t("写入平均")))

                    LineMark(
                        x: .value(L10n.t("测试顺序"), index),
                        y: .value("MB/s", result.readAverageMBps),
                        series: .value(L10n.t("指标"), L10n.t("读取平均"))
                    )
                    .foregroundStyle(by: .value(L10n.t("指标"), L10n.t("读取平均")))
                    .interpolationMethod(.linear)

                    PointMark(
                        x: .value(L10n.t("测试顺序"), index),
                        y: .value("MB/s", result.readAverageMBps)
                    )
                    .foregroundStyle(by: .value(L10n.t("指标"), L10n.t("读取平均")))
                }
            }
            .chartXAxis {
                AxisMarks(values: axisIndices) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let index = value.as(Int.self), ordered.indices.contains(index) {
                            VStack(spacing: 1) {
                                Text(ordered[index].completedAt, format: .dateTime.month().day())
                                Text(ordered[index].completedAt, format: .dateTime.hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .chartXScale(range: .plotDimension(startPadding: 6, endPadding: 6))
            .chartLegend(position: .bottom)
            .frame(height: 240)
        }
    }
}

struct SpeedResultList: View {
    @EnvironmentObject private var speedState: SpeedTestAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(speedState.resultsForSelectedTarget) { result in
                Button {
                    speedState.selectedResultID = result.id
                } label: {
                    SpeedResultRow(result: result, selected: speedState.selectedResultID == result.id)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SpeedResultRow: View {
    var result: SpeedTestResult
    var selected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "speedometer")
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(SmartFormatting.shortDateTime(result.completedAt))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text("\(SmartFormatting.sizeString(result.testSizeBytes)) · \(L10n.t(result.targetDisplayName))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let kind = result.targetConnectionKind {
                    Text(L10n.t(kind.rawValue))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(L10n.f("写 %@ / 读 %@", SmartFormatting.speedMBps(result.writeAverageMBps), SmartFormatting.speedMBps(result.readAverageMBps)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(selected ? Color.white.opacity(0.10) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Color.blue.opacity(0.35) : Color.white.opacity(0.05), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SpeedResultDetail: View {
    @EnvironmentObject private var speedState: SpeedTestAppState
    @State private var showDeleteConfirmation = false

    var body: some View {
        if let result = speedState.selectedResult {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("测速详情")
                            .font(.title3.weight(.semibold))
                        Text(SmartFormatting.shortDateTime(result.completedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                    SpeedSmallStat(title: "写入平均", value: SmartFormatting.speedMBps(result.writeAverageMBps))
                    SpeedSmallStat(title: "写入峰值", value: SmartFormatting.speedMBps(result.writePeakMBps))
                    SpeedSmallStat(title: "读取平均", value: SmartFormatting.speedMBps(result.readAverageMBps))
                    SpeedSmallStat(title: "读取峰值", value: SmartFormatting.speedMBps(result.readPeakMBps))
                }

                KeyValueRow(title: "测试大小", value: SmartFormatting.sizeString(result.testSizeBytes))
                KeyValueRow(title: "模式", value: result.mode.rawValue)
                KeyValueRow(title: "写入耗时", value: SmartFormatting.seconds(result.writeDurationSeconds))
                KeyValueRow(title: "读取耗时", value: SmartFormatting.seconds(result.readDurationSeconds))
                KeyValueRow(title: "测试目录", value: result.targetDisplayName)
                KeyValueRow(
                    title: "目标类型",
                    value: result.targetConnectionKind.map { L10n.t($0.rawValue) } ?? L10n.t(result.targetKind.rawValue)
                )
                KeyValueRow(title: "卷名", value: result.volumeName ?? "未返回")
                KeyValueRow(title: "测试前可用空间", value: SmartFormatting.sizeString(result.volumeAvailableBeforeBytes))
                KeyValueRow(title: "测试后可用空间", value: SmartFormatting.sizeString(result.volumeAvailableAfterBytes))
                KeyValueRow(
                    title: "写入无缓存请求",
                    value: result.writeNoCacheApplied.map { $0 ? L10n.t("已生效") : L10n.t("未生效") } ?? L10n.t("旧记录未保存")
                )
                KeyValueRow(
                    title: "读取无缓存请求",
                    value: result.readNoCacheApplied.map { $0 ? L10n.t("已生效") : L10n.t("未生效") } ?? L10n.t("旧记录未保存")
                )
                KeyValueRow(
                    title: "写入同步确认",
                    value: result.writeSyncSucceeded.map { $0 ? L10n.t("成功") : L10n.t("未确认") } ?? L10n.t("旧记录未保存")
                )

                if let warnings = result.measurementWarnings {
                    ForEach(warnings, id: \.self) { warning in
                        Label(L10n.t(warning), systemImage: "info.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }

                if let warning = result.cleanupWarning, !warning.isEmpty {
                    Label(L10n.t(warning), systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .confirmationDialog("删除这个速度测试历史？", isPresented: $showDeleteConfirmation) {
                Button("删除", role: .destructive) {
                    speedState.deleteResult(result)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作只删除本机测速历史，不会修改磁盘或删除测试目录。")
            }
        } else {
            ContentUnavailableView(
                "选择一条测速历史",
                systemImage: "doc.text.magnifyingglass",
                description: Text("完成或选择测速结果后可查看详情。")
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }
}

struct SpeedTestFailureCard: View {
    var failure: SpeedTestFailure

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.t(failure.title), systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
            Text(L10n.t(failure.message))
                .font(.body)
            Text(L10n.t(failure.recovery))
                .font(.callout)
                .foregroundStyle(.secondary)
            if let underlying = failure.underlyingDescription {
                Text(underlying)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .labGlassCard()
    }
}

struct SpeedTestCleanupWarningCard: View {
    var warning: String

    var body: some View {
        Label(L10n.f("测速完成，但临时文件清理需要检查：%@", L10n.t(warning)), systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .labGlassCard()
    }
}
