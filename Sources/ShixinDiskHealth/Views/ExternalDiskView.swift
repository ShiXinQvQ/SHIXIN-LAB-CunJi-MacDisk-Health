import ShixinDiskHealthCore
import SwiftUI

struct ExternalDiskView: View {
    @EnvironmentObject private var appState: DiskHealthAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ExternalDiskToolbar()

                if let failure = appState.externalLastFailure {
                    FailureView(failure: failure)
                }

                if let snapshot = appState.externalCurrentSnapshotForSelectedDisk {
                    HealthOverviewCard(snapshot: snapshot)
                    CoreMetricGrid(snapshot: snapshot)
                    if let delta = appState.externalCurrentDelta {
                        DeltaCard(delta: delta)
                    }
                    DetailSectionsView(snapshot: snapshot, showSerial: appState.showSerialNumber)
                    RawJSONCard(snapshot: snapshot)
                } else if appState.externalLastFailure == nil {
                    externalReadyState
                }
            }
            .padding(22)
        }
    }

    @ViewBuilder
    private var externalReadyState: some View {
        if appState.externalDiskTargets.isEmpty {
            ContentUnavailableView(
                L10n.t("未发现外置硬盘"),
                systemImage: "externaldrive.badge.questionmark",
                description: Text(L10n.t("连接本地 USB、Thunderbolt、NVMe 或 SATA 外置硬盘后，点击刷新。"))
            )
            .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            ContentUnavailableView(
                L10n.t("等待检测外置硬盘"),
                systemImage: "externaldrive.badge.timemachine",
                description: Text(L10n.t("确认上方所选硬盘后，点击立即检测。检测只读取 SMART，不会修改磁盘。"))
            )
            .frame(maxWidth: .infinity, minHeight: 300)
        }
    }
}

private struct ExternalDiskToolbar: View {
    @EnvironmentObject private var appState: DiskHealthAppState
    @State private var isCheckAnimationActive = false
    @State private var checkRotation: Double = 0
    @State private var showSavedPopover = false
    @State private var savedPopoverToken = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                roomyToolbar
                    .frame(minWidth: 850)
                compactToolbar
            }

            if let target = appState.selectedExternalDiskTarget {
                Divider().opacity(0.22)
                DiskTargetSummary(target: target)
            }
        }
        .labGlassCard(padding: 16, cornerRadius: 18)
    }

    private var roomyToolbar: some View {
        HStack(spacing: 14) {
            titleBlock
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(2)

            targetPicker
                .frame(width: 230)

            refreshButton
            actionButtons(controlSize: .large)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var compactToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBlock
            HStack(spacing: 8) {
                targetPicker
                refreshButton
                Spacer(minLength: 0)
                actionButtons(controlSize: .regular)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var titleBlock: some View {
        HStack(spacing: 11) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(externalAccent)
                .frame(width: 38, height: 38)
                .background(externalAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("外置硬盘检测"))
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(lastDetectionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var externalAccent: Color {
        Color(red: 0.74, green: 0.32, blue: 0.82)
    }

    private var targetPicker: some View {
        Picker(L10n.t("外置硬盘"), selection: selectedDiskBinding) {
            if appState.externalDiskTargets.isEmpty {
                Text(L10n.t("未发现外置硬盘"))
                    .tag(Optional<DiskTarget.ID>.none)
            } else {
                ForEach(appState.externalDiskTargets) { target in
                    Label(target.displayName, systemImage: target.connectionKind.symbolName)
                        .tag(Optional(target.id))
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(appState.isDetecting || appState.externalDiskTargets.isEmpty)
        .accessibilityLabel(L10n.t("外置硬盘"))
    }

    private var refreshButton: some View {
        Button {
            appState.refreshExternalDiskInventory()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(appState.isDetecting)
        .help(L10n.t("刷新外置硬盘列表"))
        .accessibilityLabel(L10n.t("刷新外置硬盘列表"))
    }

    private func actionButtons(controlSize: ControlSize) -> some View {
        HStack(spacing: 8) {
            Button {
                if appState.isDetectingExternalDisk {
                    appState.cancelExternalDetection()
                } else if !appState.isDetecting {
                    runAnimatedDetection()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: appState.isDetectingExternalDisk ? "stop.circle.fill" : "arrow.clockwise")
                        .rotationEffect(.degrees(checkRotation))
                    Text(L10n.t(appState.isDetectingExternalDisk ? "停止检测" : (isCheckAnimationActive ? "检测中" : "立即检测")))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(controlSize)
            .disabled(
                (!appState.isDetecting && isCheckAnimationActive) ||
                    (!appState.isDetecting && appState.selectedExternalDiskTarget?.canReadSMART != true) ||
                    (appState.isDetecting && !appState.isDetectingExternalDisk)
            )

            Button {
                if appState.saveExternalSnapshot() {
                    showSnapshotSavedPopover()
                }
            } label: {
                Label("保存快照", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(controlSize)
            .disabled(!appState.canSaveExternalSnapshot)
            .popover(isPresented: $showSavedPopover, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("快照已保存"))
                        .font(.headline)
                    Text(L10n.t("已写入本机历史记录，可在历史记录中回看。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(width: 320, alignment: .leading)
            }
        }
    }

    private var selectedDiskBinding: Binding<DiskTarget.ID?> {
        Binding {
            appState.selectedExternalDiskID
        } set: { newValue in
            _ = appState.selectExternalDisk(id: newValue)
        }
    }

    private var lastDetectionText: String {
        guard let snapshot = appState.externalCurrentSnapshotForSelectedDisk else {
            return L10n.t("选择外置硬盘后开始只读检测")
        }
        return L10n.f("最近检测：%@", SmartFormatting.shortDateTime(snapshot.capturedAt))
    }

    private func runAnimatedDetection() {
        guard !appState.isDetecting && !isCheckAnimationActive else { return }
        isCheckAnimationActive = true
        checkRotation = 0
        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
            checkRotation = 360
        }

        Task { @MainActor in
            await appState.runExternalDetection()
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
}
