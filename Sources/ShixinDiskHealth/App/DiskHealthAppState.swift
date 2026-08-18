import AppKit
import Foundation
import ServiceManagement
import ShixinDiskHealthCore
import SwiftUI
import UniformTypeIdentifiers

struct DiskHistoryGroup: Identifiable, Hashable {
    var identityRawValue: String
    var identitySource: String
    var displayName: String
    var modelName: String?
    var connectionKind: DiskConnectionKind?
    var isConnected: Bool
    var snapshots: [SmartSnapshot]

    var id: String { identityRawValue }
}

private enum DetectionScope {
    case internalDisk
    case externalDisk
}

@MainActor
final class DiskHealthAppState: ObservableObject {
    @Published var currentSnapshot: SmartSnapshot?
    @Published var externalCurrentSnapshot: SmartSnapshot?
    @Published var snapshots: [SmartSnapshot] = []
    @Published var selectedSnapshotID: SmartSnapshot.ID?
    @Published var lastFailure: SmartctlFailure?
    @Published var externalLastFailure: SmartctlFailure?
    @Published var historyFailure: SmartctlFailure?
    @Published var isDetecting = false
    @Published var showSerialNumber = false
    @Published var showPrivateHardwareIdentifiers = UserDefaults.standard.bool(forKey: "com.shixinqvq.shixinlab.diskhealth.showPrivateHardwareIdentifiers")
    @Published var hardwareProfile = HardwareProfile.loading
    @Published var manualSmartctlPath = UserDefaults.standard.string(forKey: "manualSmartctlPath") ?? ""
    @Published var lastSavedMessage: String?
    @Published var diskInventory = DiskInventory()
    @Published var selectedDiskID: DiskTarget.ID?
    @Published var selectedExternalDiskID: DiskTarget.ID?
    @Published var selectedHistoryIdentity: String?

    let store = SnapshotStore()
    let helperManager = PrivilegedHelperManager()
    private let runner: SmartctlRunner
    private var didRunInitialDetection = false
    private var hardwareProfileTask: Task<Void, Never>?
    private var hardwareProfileGeneration = UUID()
    private var activeDetectionTask: Task<SmartctlReadOutcome, Never>?
    private var detectionGeneration = UUID()
    private var activeDetectionScope: DetectionScope?
    private static let showPrivateHardwareIdentifiersKey = "com.shixinqvq.shixinlab.diskhealth.showPrivateHardwareIdentifiers"

    init() {
        var roots: [URL] = []
        if let mainResourceURL = Bundle.main.resourceURL {
            roots.append(mainResourceURL)
        }
        self.runner = SmartctlRunner(resourceRoots: roots)
        loadSnapshots()
    }

    var selectedSnapshot: SmartSnapshot? {
        let available = snapshotsForSelectedHistoryGroup
        guard let selectedSnapshotID else { return available.first }
        return available.first { $0.id == selectedSnapshotID } ?? available.first
    }

    var previousSavedSnapshotForCurrent: SmartSnapshot? {
        guard let currentSnapshot = currentSnapshotForSelectedDisk else { return nil }
        return snapshots
            .filter { $0.effectiveDiskIdentity.rawValue == currentSnapshot.effectiveDiskIdentity.rawValue }
            .filter { $0.capturedAt < currentSnapshot.capturedAt }
            .sorted { $0.capturedAt > $1.capturedAt }
            .first
    }

    var currentDelta: SnapshotDelta? {
        guard let currentSnapshot = currentSnapshotForSelectedDisk, let previous = previousSavedSnapshotForCurrent else { return nil }
        return SnapshotDelta(current: currentSnapshot, previous: previous)
    }

    var selectedDiskTarget: DiskTarget? {
        if let selectedDiskID, let target = internalDiskTargets.first(where: { $0.id == selectedDiskID }) {
            return target
        }
        if let preferred = preferredInternalTargetID {
            return internalDiskTargets.first { $0.id == preferred }
        }
        return internalDiskTargets.first
    }

    var selectedExternalDiskTarget: DiskTarget? {
        if let selectedExternalDiskID,
           let target = externalDiskTargets.first(where: { $0.id == selectedExternalDiskID }) {
            return target
        }
        return externalDiskTargets.first
    }

    var internalDiskTargets: [DiskTarget] {
        diskInventory.smartTargets.filter { $0.connectionKind == .internalPhysical || $0.isInternal == true }
    }

    var externalDiskTargets: [DiskTarget] {
        diskInventory.smartTargets.filter { $0.connectionKind == .externalPhysical && $0.isInternal != true }
    }

    var isDetectingInternalDisk: Bool {
        isDetecting && activeDetectionScope == .internalDisk
    }

    var isDetectingExternalDisk: Bool {
        isDetecting && activeDetectionScope == .externalDisk
    }

    var snapshotsForSelectedDisk: [SmartSnapshot] {
        guard let currentSnapshotForSelectedDisk else { return [] }
        let identity = currentSnapshotForSelectedDisk.effectiveDiskIdentity.rawValue
        return snapshots.filter { $0.effectiveDiskIdentity.rawValue == identity }
    }

    var historyGroups: [DiskHistoryGroup] {
        let grouped = Dictionary(grouping: snapshots) { $0.effectiveDiskIdentity.rawValue }
        return grouped.compactMap { identityRawValue, values in
            guard let newest = values.max(by: { $0.capturedAt < $1.capturedAt }) else { return nil }
            let connected = diskInventory.smartTargets.contains { target in
                values.contains { $0.belongs(to: target) }
            }
            return DiskHistoryGroup(
                identityRawValue: identityRawValue,
                identitySource: newest.effectiveDiskIdentity.source,
                displayName: newest.diskDisplayName ?? newest.device.modelName ?? newest.device.deviceName,
                modelName: newest.device.modelName,
                connectionKind: newest.diskConnectionKind,
                isConnected: connected,
                snapshots: values.sorted { $0.capturedAt > $1.capturedAt }
            )
        }
        .sorted { lhs, rhs in
            (lhs.snapshots.first?.capturedAt ?? .distantPast) > (rhs.snapshots.first?.capturedAt ?? .distantPast)
        }
    }

    var selectedHistoryGroup: DiskHistoryGroup? {
        if let selectedHistoryIdentity,
           let group = historyGroups.first(where: { $0.identityRawValue == selectedHistoryIdentity }) {
            return group
        }
        return historyGroups.first
    }

    var snapshotsForSelectedHistoryGroup: [SmartSnapshot] {
        selectedHistoryGroup?.snapshots ?? []
    }

    var currentSnapshotForSelectedDisk: SmartSnapshot? {
        guard let currentSnapshot, let target = selectedDiskTarget, currentSnapshot.belongs(to: target) else {
            return nil
        }
        return currentSnapshot
    }

    var externalCurrentSnapshotForSelectedDisk: SmartSnapshot? {
        guard let externalCurrentSnapshot,
              let target = selectedExternalDiskTarget,
              externalCurrentSnapshot.belongs(to: target) else {
            return nil
        }
        return externalCurrentSnapshot
    }

    var externalCurrentDelta: SnapshotDelta? {
        guard let current = externalCurrentSnapshotForSelectedDisk else { return nil }
        let previous = snapshots
            .filter { $0.effectiveDiskIdentity.rawValue == current.effectiveDiskIdentity.rawValue }
            .filter { $0.capturedAt < current.capturedAt }
            .sorted { $0.capturedAt > $1.capturedAt }
            .first
        guard let previous else { return nil }
        return SnapshotDelta(current: current, previous: previous)
    }

    var canSaveCurrentSnapshot: Bool {
        currentSnapshotForSelectedDisk != nil && !isDetecting
    }

    var canSaveExternalSnapshot: Bool {
        externalCurrentSnapshotForSelectedDisk != nil && !isDetecting
    }

    func runInitialDetection() async {
        guard !didRunInitialDetection else { return }
        didRunInitialDetection = true
        await runDetection()
    }

    func runDetection() async {
        await runDetection(scope: .internalDisk)
    }

    func runExternalDetection() async {
        await runDetection(scope: .externalDisk)
    }

    private func runDetection(scope: DetectionScope) async {
        guard !isDetecting else { return }
        let requestedSelection = selectedDiskID(for: scope)
        let requestedTarget = requestedSelection.flatMap { id in
            diskInventory.smartTargets.first { $0.id == id }
        }
        clearCurrentResult(for: scope)

        let refreshedInventory = DiskInventoryReader.read()
        diskInventory = refreshedInventory
        initializeMissingSelections(in: refreshedInventory)

        let target: DiskTarget?
        if let requestedTarget {
            let matched = refreshedInventory.smartTarget(matching: requestedTarget)
            target = matched.flatMap { targetMatches($0, scope: scope) ? $0 : nil }
        } else if requestedSelection == nil {
            target = defaultTarget(for: scope, in: refreshedInventory)
        } else {
            target = nil
        }

        guard let target, target.canReadSMART, target.smartctlAccessProfile != nil else {
            setSelectedDiskID(defaultTarget(for: scope, in: refreshedInventory)?.id, for: scope)
            alignSelectedHistoryGroup()
            alignSelectedSnapshotToDiskFilter()
            if requestedSelection != nil {
                setFailure(SmartctlFailure(
                    title: "所选硬盘已断开或身份已改变",
                    message: "检测前重新核对磁盘时，原目标已不存在或设备身份不再一致；本次不会自动改读其他硬盘。",
                    recovery: "请确认当前磁盘列表和目标名称，再点击立即检测。已保存历史仍可在历史记录页查看。"
                ), for: scope)
                return
            }
            let isExternal = scope == .externalDisk
            setFailure(SmartctlFailure(
                title: isExternal ? "没有可检测的外置硬盘" : "没有可检测的内置硬盘",
                message: isExternal
                    ? "当前没有找到可尝试读取 SMART 的本地外置 whole-disk 设备。"
                    : "当前没有找到可读取 SMART 的内置 whole-disk 设备。",
                recovery: isExternal
                    ? "请连接外置硬盘后刷新列表。网络卷只支持文件测速，不提供 SMART 检测。"
                    : "请刷新磁盘列表；当前报告不会自动切换到外置硬盘。"
            ), for: scope)
            return
        }
        setSelectedDiskID(target.id, for: scope)
        isDetecting = true
        activeDetectionScope = scope
        let generation = UUID()
        detectionGeneration = generation
        defer {
            if detectionGeneration == generation {
                isDetecting = false
                activeDetectionTask = nil
                activeDetectionScope = nil
            }
        }
        let manualPath = manualSmartctlPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = Task {
            await runner.read(target: target, manualPath: manualPath.isEmpty ? nil : manualPath)
        }
        activeDetectionTask = task
        let outcome = await task.value
        guard detectionGeneration == generation, selectedDiskID(for: scope) == target.id else { return }
        switch outcome {
        case .success(let snapshot):
            guard snapshot.belongs(to: target), snapshot.diskDevicePath == target.devicePath else {
                setFailure(SmartctlFailure(
                    title: "读取结果与所选硬盘不一致",
                    message: "检测结果没有绑定到当前选择的硬盘，已拒绝展示和保存。",
                    recovery: "请刷新磁盘列表后重新检测；如果问题持续出现，请保留诊断信息。"
                ), for: scope)
                return
            }
            setSnapshot(snapshot, for: scope)
        case .failure(let failure):
            setFailure(failure, for: scope)
        }
    }

    func loadSnapshots() {
        historyFailure = nil
        do {
            _ = try store.importPreviousVersionHistoryIfNeeded()
        } catch {
            historyFailure = SmartctlFailure(
                title: "旧版 SMART 历史导入失败",
                message: error.localizedDescription,
                recovery: "旧版原始记录没有被修改；当前版本会继续读取自己的历史记录。"
            )
        }
        do {
            snapshots = try store.load()
            alignSelectedHistoryGroup()
            alignSelectedSnapshotToDiskFilter()
        } catch {
            historyFailure = SmartctlFailure(
                title: "历史记录读取失败",
                message: error.localizedDescription,
                recovery: "当前检测仍可继续，历史文件可能需要手动备份后重建。"
            )
        }
    }

    func refreshDiskInventory() {
        let previousInternalTarget = selectedDiskTarget
        let previousInternalSelection = selectedDiskID
        let previousExternalTarget = selectedExternalDiskTarget
        let previousExternalSelection = selectedExternalDiskID
        cancelActiveDetection()
        currentSnapshot = nil
        externalCurrentSnapshot = nil
        lastFailure = nil
        externalLastFailure = nil
        let refreshedInventory = DiskInventoryReader.read()
        diskInventory = refreshedInventory
        let refreshedInternalTarget = previousInternalTarget
            .flatMap { refreshedInventory.smartTarget(matching: $0) }
            .flatMap { targetMatches($0, scope: .internalDisk) ? $0 : nil }
        let refreshedExternalTarget = previousExternalTarget
            .flatMap { refreshedInventory.smartTarget(matching: $0) }
            .flatMap { targetMatches($0, scope: .externalDisk) ? $0 : nil }
        selectedDiskID = refreshedInternalTarget?.id ?? defaultTarget(for: .internalDisk, in: refreshedInventory)?.id
        selectedExternalDiskID = refreshedExternalTarget?.id ?? defaultTarget(for: .externalDisk, in: refreshedInventory)?.id
        if previousInternalSelection != nil, refreshedInternalTarget == nil {
            lastFailure = SmartctlFailure(
                title: "先前选择的内置硬盘已不可用",
                message: "磁盘列表刷新后，先前内置目标已不再存在、身份已改变或无法唯一确认；不会改读外置硬盘，也不会沿用旧结果。",
                recovery: "请确认当前选择，再点击立即检测。已保存历史仍可在历史记录页按离线硬盘查看。"
            )
        }
        if previousExternalSelection != nil, refreshedExternalTarget == nil {
            externalLastFailure = SmartctlFailure(
                title: "先前选择的外置硬盘已断开",
                message: "磁盘列表刷新后，先前外置目标已不再存在、身份已改变或无法唯一确认；不会沿用旧检测结果。",
                recovery: "请重新连接硬盘或选择当前列表中的其他外置硬盘。已保存历史仍可在历史记录页查看。"
            )
        }
        alignSelectedHistoryGroup()
        alignSelectedSnapshotToDiskFilter()
    }

    func refreshExternalDiskInventory() {
        let previousInternalTarget = selectedDiskTarget
        let previousExternalTarget = selectedExternalDiskTarget
        let previousExternalSelection = selectedExternalDiskID
        cancelActiveDetection()
        externalCurrentSnapshot = nil
        externalLastFailure = nil

        let refreshedInventory = DiskInventoryReader.read()
        diskInventory = refreshedInventory

        if let previousInternalTarget,
           let refreshedInternal = refreshedInventory.smartTarget(matching: previousInternalTarget),
           targetMatches(refreshedInternal, scope: .internalDisk) {
            selectedDiskID = refreshedInternal.id
        } else {
            selectedDiskID = defaultTarget(for: .internalDisk, in: refreshedInventory)?.id
            currentSnapshot = nil
        }

        let refreshedExternal = previousExternalTarget
            .flatMap { refreshedInventory.smartTarget(matching: $0) }
            .flatMap { targetMatches($0, scope: .externalDisk) ? $0 : nil }
        selectedExternalDiskID = refreshedExternal?.id ?? defaultTarget(for: .externalDisk, in: refreshedInventory)?.id
        if previousExternalSelection != nil, refreshedExternal == nil {
            externalLastFailure = SmartctlFailure(
                title: "先前选择的外置硬盘已断开",
                message: "刷新后无法确认先前的外置硬盘；旧检测结果已清除，不会显示成其他硬盘的数据。",
                recovery: "请重新连接硬盘或选择当前列表中的其他外置硬盘。"
            )
        }
        alignSelectedHistoryGroup()
        alignSelectedSnapshotToDiskFilter()
    }

    @discardableResult
    func selectDisk(id: DiskTarget.ID?) -> Bool {
        guard let id,
              internalDiskTargets.contains(where: { $0.id == id }),
              selectedDiskID != id else {
            return false
        }
        selectedDiskID = id
        cancelActiveDetection()
        currentSnapshot = nil
        lastFailure = nil
        lastSavedMessage = nil
        alignSelectedSnapshotToDiskFilter()
        return true
    }

    @discardableResult
    func selectExternalDisk(id: DiskTarget.ID?) -> Bool {
        guard let id,
              externalDiskTargets.contains(where: { $0.id == id }),
              selectedExternalDiskID != id else {
            return false
        }
        selectedExternalDiskID = id
        cancelActiveDetection()
        externalCurrentSnapshot = nil
        externalLastFailure = nil
        lastSavedMessage = nil
        return true
    }

    func cancelDetection() {
        guard activeDetectionScope == .internalDisk else { return }
        cancelActiveDetection()
        lastFailure = SmartctlFailure(
            title: "SMART 检测已取消",
            message: "所选硬盘的只读检测任务已停止。",
            recovery: "确认硬盘仍已连接后可以重新检测。"
        )
    }

    func cancelExternalDetection() {
        guard activeDetectionScope == .externalDisk else { return }
        cancelActiveDetection()
        externalLastFailure = SmartctlFailure(
            title: "外置硬盘检测已取消",
            message: "所选外置硬盘的只读检测任务已停止。",
            recovery: "确认硬盘仍已连接后可以重新检测。"
        )
    }

    private func cancelActiveDetection() {
        activeDetectionTask?.cancel()
        activeDetectionTask = nil
        detectionGeneration = UUID()
        isDetecting = false
        activeDetectionScope = nil
    }

    func alignSelectedSnapshotToDiskFilter() {
        let available = snapshotsForSelectedHistoryGroup
        if let selectedSnapshotID, available.contains(where: { $0.id == selectedSnapshotID }) {
            return
        }
        selectedSnapshotID = available.first?.id
    }

    func selectHistoryGroup(identityRawValue: String?) {
        guard selectedHistoryIdentity != identityRawValue else { return }
        selectedHistoryIdentity = identityRawValue
        alignSelectedSnapshotToDiskFilter()
    }

    private func alignSelectedHistoryGroup() {
        let groups = historyGroups
        if let selectedHistoryIdentity,
           groups.contains(where: { $0.identityRawValue == selectedHistoryIdentity }) {
            return
        }
        selectedHistoryIdentity = groups.first?.identityRawValue
    }

    @discardableResult
    func saveCurrentSnapshot() -> Bool {
        guard let currentSnapshot = currentSnapshotForSelectedDisk, !isDetecting else { return false }
        return saveSnapshot(currentSnapshot, failureScope: .internalDisk)
    }

    @discardableResult
    func saveExternalSnapshot() -> Bool {
        guard let snapshot = externalCurrentSnapshotForSelectedDisk, !isDetecting else { return false }
        return saveSnapshot(snapshot, failureScope: .externalDisk)
    }

    private func saveSnapshot(_ snapshot: SmartSnapshot, failureScope: DetectionScope) -> Bool {
        do {
            snapshots = try store.append(snapshot)
            selectedHistoryIdentity = snapshot.effectiveDiskIdentity.rawValue
            selectedSnapshotID = snapshot.id
            lastSavedMessage = "已保存快照：\(SmartFormatting.shortDateTime(snapshot.capturedAt))"
            setFailure(nil, for: failureScope)
            return true
        } catch {
            setFailure(SmartctlFailure(
                title: "历史记录保存失败",
                message: error.localizedDescription,
                recovery: "请检查应用支持目录是否可写：\(store.appSupportDirectory.path)"
            ), for: failureScope)
            return false
        }
    }

    private var preferredInternalTargetID: DiskTarget.ID? {
        defaultTarget(for: .internalDisk, in: diskInventory)?.id
    }

    private func defaultTarget(for scope: DetectionScope, in inventory: DiskInventory) -> DiskTarget? {
        let candidates = inventory.smartTargets.filter { targetMatches($0, scope: scope) }
        switch scope {
        case .internalDisk:
            return candidates.first(where: { $0.devicePath == "/dev/disk0" }) ?? candidates.first
        case .externalDisk:
            return candidates.first
        }
    }

    private func targetMatches(_ target: DiskTarget, scope: DetectionScope) -> Bool {
        switch scope {
        case .internalDisk:
            return target.connectionKind == .internalPhysical || target.isInternal == true
        case .externalDisk:
            return target.connectionKind == .externalPhysical && target.isInternal != true
        }
    }

    private func initializeMissingSelections(in inventory: DiskInventory) {
        if selectedDiskID == nil {
            selectedDiskID = defaultTarget(for: .internalDisk, in: inventory)?.id
        }
        if selectedExternalDiskID == nil {
            selectedExternalDiskID = defaultTarget(for: .externalDisk, in: inventory)?.id
        }
    }

    private func selectedDiskID(for scope: DetectionScope) -> DiskTarget.ID? {
        switch scope {
        case .internalDisk: selectedDiskID
        case .externalDisk: selectedExternalDiskID
        }
    }

    private func setSelectedDiskID(_ id: DiskTarget.ID?, for scope: DetectionScope) {
        switch scope {
        case .internalDisk: selectedDiskID = id
        case .externalDisk: selectedExternalDiskID = id
        }
    }

    private func clearCurrentResult(for scope: DetectionScope) {
        setSnapshot(nil, for: scope)
        setFailure(nil, for: scope)
        lastSavedMessage = nil
    }

    private func setSnapshot(_ snapshot: SmartSnapshot?, for scope: DetectionScope) {
        switch scope {
        case .internalDisk: currentSnapshot = snapshot
        case .externalDisk: externalCurrentSnapshot = snapshot
        }
    }

    private func setFailure(_ failure: SmartctlFailure?, for scope: DetectionScope) {
        switch scope {
        case .internalDisk: lastFailure = failure
        case .externalDisk: externalLastFailure = failure
        }
    }

    func deleteSnapshot(_ snapshot: SmartSnapshot) {
        do {
            snapshots = try store.delete(id: snapshot.id)
            historyFailure = nil
            alignSelectedHistoryGroup()
            if selectedSnapshotID == snapshot.id {
                selectedSnapshotID = snapshotsForSelectedHistoryGroup.first?.id
            }
        } catch {
            historyFailure = SmartctlFailure(
                title: "历史记录删除失败",
                message: error.localizedDescription,
                recovery: "请检查历史记录文件权限：\(store.snapshotsURL.path)"
            )
        }
    }

    func refreshHardwareProfile() {
        hardwareProfileTask?.cancel()
        let generation = UUID()
        hardwareProfileGeneration = generation
        hardwareProfile = .loading
        let showPrivateHardwareIdentifiers = showPrivateHardwareIdentifiers
        hardwareProfileTask = Task { [weak self] in
            let profile = await Task.detached(priority: .utility) {
                await HardwareProfileReader.read(showPrivateIdentifiers: showPrivateHardwareIdentifiers)
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.hardwareProfileGeneration == generation,
                  self.showPrivateHardwareIdentifiers == showPrivateHardwareIdentifiers else { return }
            self.hardwareProfile = profile
        }
    }

    func setShowPrivateHardwareIdentifiers(_ show: Bool) {
        showPrivateHardwareIdentifiers = show
        UserDefaults.standard.set(show, forKey: Self.showPrivateHardwareIdentifiersKey)
        refreshHardwareProfile()
    }

    func persistManualPath() {
        let trimmed = manualSmartctlPath.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: "manualSmartctlPath")
    }

    func chooseManualSmartctlPath() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("选择 smartctl")
        panel.prompt = L10n.t("选择")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            manualSmartctlPath = url.path
            persistManualPath()
        }
    }

    func exportSnapshots(format: ExportFormat) {
        guard confirmDeviceInfoExport() else { return }
        let panel = NSSavePanel()
        panel.title = L10n.t("导出健康报告")
        panel.nameFieldStringValue = "SHIXIN-LAB-CunJi-MacDisk-Health-\(SmartFormatting.fileDate(Date())).\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let exportSnapshots = snapshotsForSelectedHistoryGroup
            switch format {
            case .json:
                try store.exportJSON(exportSnapshots, to: url)
            case .csv:
                try store.exportCSV(exportSnapshots, to: url)
            }
            historyFailure = nil
        } catch {
            historyFailure = SmartctlFailure(
                title: "导出失败",
                message: error.localizedDescription,
                recovery: "请确认目标位置可写，然后重试。"
            )
        }
    }

    private func confirmDeviceInfoExport() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.t("导出报告可能包含设备信息")
        alert.informativeText = L10n.t("导出的历史记录可能包含完整硬盘序列号、硬盘型号、固件版本、SMART 原始数据等设备信息。请谨慎保存和分享。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.t("继续导出"))
        alert.addButton(withTitle: L10n.t("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

enum ExportFormat {
    case json
    case csv

    var fileExtension: String {
        switch self {
        case .json: "json"
        case .csv: "csv"
        }
    }

    var contentType: UTType {
        switch self {
        case .json: .json
        case .csv: .commaSeparatedText
        }
    }
}
