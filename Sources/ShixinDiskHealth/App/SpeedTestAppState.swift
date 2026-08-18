import AppKit
import Foundation
import ShixinDiskHealthCore
import UniformTypeIdentifiers

struct SpeedTestHistoryGroup: Identifiable, Hashable {
    var key: String
    var displayName: String
    var connectionKind: DiskConnectionKind?
    var results: [SpeedTestResult]

    var id: String { key }
}

@MainActor
final class SpeedTestAppState: ObservableObject {
    @Published var selectedSize: SpeedTestSizeOption = .defaultOption
    @Published var selectedMode: SpeedTestMode = .single
    @Published var targetKind: SpeedTestTargetKind = .defaultCacheDirectory
    @Published var selectedDirectoryURL: URL?
    @Published var selectedDiskTarget: DiskTarget?
    @Published var results: [SpeedTestResult] = []
    @Published var selectedResultID: SpeedTestResult.ID?
    @Published var selectedHistoryGroupKey: String?
    @Published var progress = SpeedTestProgress()
    @Published var isRunning = false
    @Published var lastFailure: SpeedTestFailure?
    @Published var lastCleanupWarning: String?

    let store = SpeedTestStore()
    private let runner: SpeedTestRunner
    private var currentTask: Task<Void, Never>?

    init() {
        self.runner = SpeedTestRunner(store: store)
        prepareStorage()
        importPublishedHistory()
        loadResults()
    }

    private func importPublishedHistory() {
        do {
            _ = try store.importPreviousVersionHistoryIfNeeded()
        } catch {
            lastFailure = SpeedTestFailure(
                title: "旧版测速历史导入失败",
                message: error.localizedDescription,
                recovery: "旧版原始记录没有被修改；请检查当前数据目录权限后重试。"
            )
        }
    }

    var selectedResult: SpeedTestResult? {
        guard let selectedResultID else { return resultsForSelectedTarget.first }
        return resultsForSelectedTarget.first { $0.id == selectedResultID } ?? resultsForSelectedTarget.first
    }

    var latestResult: SpeedTestResult? {
        results
            .filter { $0.historyGroupKey == currentTargetHistoryGroupKey }
            .max { $0.completedAt < $1.completedAt }
    }

    var historyGroups: [SpeedTestHistoryGroup] {
        Dictionary(grouping: results, by: \.historyGroupKey)
            .map { key, values in
                let ordered = values.sorted { $0.completedAt > $1.completedAt }
                let newest = ordered[0]
                return SpeedTestHistoryGroup(
                    key: key,
                    displayName: newest.targetDisplayName,
                    connectionKind: newest.targetConnectionKind,
                    results: ordered
                )
            }
            .sorted {
                ($0.results.first?.completedAt ?? .distantPast) > ($1.results.first?.completedAt ?? .distantPast)
            }
    }

    var resultsForSelectedTarget: [SpeedTestResult] {
        if let selectedHistoryGroupKey,
           let group = historyGroups.first(where: { $0.key == selectedHistoryGroupKey }) {
            return group.results
        }
        return historyGroups.first?.results ?? []
    }

    var currentTargetDirectory: URL {
        switch targetKind {
        case .defaultCacheDirectory:
            store.defaultCacheDirectory
        case .userSelectedDirectory:
            selectedDirectoryURL ?? store.defaultCacheDirectory
        }
    }

    var currentTargetDisplayName: String {
        selectedDiskTarget?.displayName ?? SpeedTestPathPolicy.displayName(for: currentTargetDirectory, kind: targetKind)
    }

    var currentTargetDescription: String {
        switch targetKind {
        case .defaultCacheDirectory:
            "默认临时目录（App 缓存）"
        case .userSelectedDirectory:
            if let selectedDiskTarget {
                "\(selectedDiskTarget.displayName)（\(selectedDiskTarget.connectionKind.rawValue)）"
            } else {
                "\(currentTargetDisplayName)（用户选择目录）"
            }
        }
    }

    func prepareStorage() {
        do {
            try store.ensureDefaultCacheDirectory()
            try store.cleanupIncompleteTests()
        } catch let failure as SpeedTestFailure {
            lastFailure = failure
        } catch {
            lastFailure = SpeedTestFailure(
                title: "速度测试存储准备失败",
                message: "无法准备默认临时目录或清理上次残留文件。",
                recovery: "请检查 App 缓存目录权限后重试。",
                underlyingDescription: error.localizedDescription
            )
        }
    }

    func loadResults() {
        do {
            results = try store.load()
            alignSelectedHistoryGroup()
        } catch {
            lastFailure = SpeedTestFailure(
                title: "速度测试历史读取失败",
                message: error.localizedDescription,
                recovery: "当前测速仍可继续，历史文件可能需要手动备份后重建。"
            )
        }
    }

    func chooseTargetDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("选择速度测试目录")
        panel.prompt = L10n.t("选择")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L10n.t("选择哪个目录，就测试该目录所在卷的普通文件读写速度。默认目录通常位于内置系统数据卷。")
        if panel.runModal() == .OK, let url = panel.url {
            selectedDirectoryURL = url
            selectedDiskTarget = nil
            targetKind = .userSelectedDirectory
            didSelectTarget()
        }
    }

    func useDefaultTargetDirectory() {
        selectedDirectoryURL = nil
        selectedDiskTarget = nil
        targetKind = .defaultCacheDirectory
        didSelectTarget()
    }

    func useDiskTargetVolume(_ target: DiskTarget) {
        guard let volumeURL = target.volumeURL else { return }
        selectedDirectoryURL = volumeURL.path == "/" ? store.defaultCacheDirectory : volumeURL
        selectedDiskTarget = target
        targetKind = volumeURL.path == "/" ? .defaultCacheDirectory : .userSelectedDirectory
        didSelectTarget()
    }

    func startOrStop() {
        if isRunning {
            stopSpeedTest()
        } else {
            startSpeedTest()
        }
    }

    func startSpeedTest() {
        guard !isRunning else { return }
        guard confirmSpeedTestStart() else { return }

        lastFailure = nil
        lastCleanupWarning = nil
        progress = SpeedTestProgress(
            phase: .preparing,
            testSizeBytes: selectedSize.bytes,
            cycleIndex: 1
        )
        isRunning = true

        let size = selectedSize
        let mode = selectedMode
        let directory = currentTargetDirectory
        let kind = targetKind
        let diskTarget = selectedDiskTarget
        let version = appVersion

        currentTask = Task {
            await runSpeedTests(
                size: size,
                mode: mode,
                targetDirectory: directory,
                targetKind: kind,
                targetDisk: diskTarget,
                appVersion: version
            )
        }
    }

    func stopSpeedTest() {
        currentTask?.cancel()
        progress = SpeedTestProgress(
            phase: .cancelled,
            testSizeBytes: selectedSize.bytes,
            cycleIndex: progress.cycleIndex
        )
    }

    func deleteResult(_ result: SpeedTestResult) {
        do {
            results = try store.delete(id: result.id)
            alignSelectedHistoryGroup()
            if selectedResultID == result.id {
                selectedResultID = resultsForSelectedTarget.first?.id
            }
        } catch {
            lastFailure = SpeedTestFailure(
                title: "速度测试历史删除失败",
                message: error.localizedDescription,
                recovery: "请检查速度测试历史文件权限：\(store.resultsURL.path)"
            )
        }
    }

    func exportResults(format: ExportFormat) {
        guard confirmSpeedTestExport() else { return }
        let panel = NSSavePanel()
        panel.title = L10n.t("导出速度测试历史")
        panel.nameFieldStringValue = "SHIXIN-LAB-CunJi-MacDisk-SpeedTest-\(SmartFormatting.fileDate(Date())).\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch format {
            case .json:
                try store.exportJSON(resultsForSelectedTarget, to: url)
            case .csv:
                try store.exportCSV(resultsForSelectedTarget, to: url)
            }
        } catch {
            lastFailure = SpeedTestFailure(
                title: "速度测试导出失败",
                message: error.localizedDescription,
                recovery: "请确认目标位置可写，然后重试。"
            )
        }
    }

    private func runSpeedTests(
        size: SpeedTestSizeOption,
        mode: SpeedTestMode,
        targetDirectory: URL,
        targetKind: SpeedTestTargetKind,
        targetDisk: DiskTarget?,
        appVersion: String
    ) async {
        var cycleIndex = 1
        defer {
            isRunning = false
            currentTask = nil
        }

        while !Task.isCancelled {
            let configuration = SpeedTestConfiguration(
                sizeOption: size,
                mode: mode,
                targetDirectory: targetDirectory,
                targetKind: targetKind,
                targetDiskIdentity: targetDisk?.identityKey,
                targetConnectionKind: targetDisk?.connectionKind,
                targetDiskDisplayName: targetDisk?.displayName,
                cycleIndex: cycleIndex,
                appVersion: appVersion
            )

            do {
                let result = try await runner.run(configuration: configuration) { [weak self] newProgress in
                    self?.progress = newProgress
                }
                results = try store.append(result)
                selectedHistoryGroupKey = result.historyGroupKey
                selectedResultID = result.id
                lastCleanupWarning = result.cleanupWarning
                if mode == .single {
                    break
                }
                cycleIndex += 1
            } catch is CancellationError {
                progress = SpeedTestProgress(
                    phase: .cancelled,
                    testSizeBytes: size.bytes,
                    cycleIndex: cycleIndex
                )
                break
            } catch let failure as SpeedTestFailure {
                lastFailure = failure
                progress = SpeedTestProgress(
                    phase: .failed,
                    testSizeBytes: size.bytes,
                    cycleIndex: cycleIndex
                )
                break
            } catch {
                lastFailure = SpeedTestFailure(
                    title: "速度测试失败",
                    message: "普通文件读写测试未能完成。",
                    recovery: "请确认测试目录可写、空间充足，并关闭其他大量读写任务后重试。",
                    underlyingDescription: error.localizedDescription
                )
                progress = SpeedTestProgress(
                    phase: .failed,
                    testSizeBytes: size.bytes,
                    cycleIndex: cycleIndex
                )
                break
            }
        }
    }

    private func confirmSpeedTestStart() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.t("开始速度测试？")
        alert.informativeText = L10n.f("开始速度测试说明", selectedSize.title)
        alert.alertStyle = .warning
        if selectedMode == .continuous {
            alert.accessoryView = continuousModeWarningView()
        }
        alert.addButton(withTitle: L10n.t("开始测试"))
        alert.addButton(withTitle: L10n.t("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func continuousModeWarningView() -> NSView {
        let warning = """
        \(L10n.t("连续模式会反复写入测试文件。"))
        \(L10n.t("获得所需结果后请手动停止，避免不必要的存储写入量。"))
        """
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 42))
        let label = NSTextField(labelWithString: warning)
        label.frame = container.bounds
        label.autoresizingMask = [.width, .height]
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = container.frame.width
        container.addSubview(label)
        return container
    }

    private func confirmSpeedTestExport() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.t("导出速度测试历史？")
        alert.informativeText = L10n.t("导出的文件包含测速时间、速度、测试大小、目标目录描述、卷名、容量信息，以及可能存在的本机目标标识（例如媒体 UUID）。不包含 SMART 原始 JSON、硬盘序列号或完整自选目录路径。")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.t("继续导出"))
        alert.addButton(withTitle: L10n.t("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "v2"
    }

    func selectHistoryGroup(key: String?) {
        guard selectedHistoryGroupKey != key else { return }
        selectedHistoryGroupKey = key
        selectedResultID = resultsForSelectedTarget.first?.id
    }

    private func alignSelectedHistoryGroup() {
        let groups = historyGroups
        if let selectedHistoryGroupKey,
           groups.contains(where: { $0.key == selectedHistoryGroupKey }) {
            if selectedResultID == nil || !resultsForSelectedTarget.contains(where: { $0.id == selectedResultID }) {
                selectedResultID = resultsForSelectedTarget.first?.id
            }
            return
        }
        selectedHistoryGroupKey = groups.first?.key
        selectedResultID = groups.first?.results.first?.id
    }

    private func selectCurrentTargetHistoryIfAvailable() {
        let key = currentTargetHistoryGroupKey
        if historyGroups.contains(where: { $0.key == key }) {
            selectHistoryGroup(key: key)
        } else {
            alignSelectedHistoryGroup()
        }
    }

    private var currentTargetHistoryGroupKey: String {
        let volumeName = selectedDiskTarget?.volumeName
            ?? (try? currentTargetDirectory.resourceValues(forKeys: [.volumeNameKey]).volumeName)
        return SpeedTestResult.makeHistoryGroupKey(
            targetDiskIdentity: selectedDiskTarget?.identityKey,
            targetConnectionKind: selectedDiskTarget?.connectionKind,
            targetKind: targetKind,
            targetDisplayName: currentTargetDisplayName,
            volumeName: volumeName
        )
    }

    private func didSelectTarget() {
        guard !isRunning else { return }
        progress = SpeedTestProgress()
        lastFailure = nil
        lastCleanupWarning = nil
        selectCurrentTargetHistoryIfAvailable()
    }
}
