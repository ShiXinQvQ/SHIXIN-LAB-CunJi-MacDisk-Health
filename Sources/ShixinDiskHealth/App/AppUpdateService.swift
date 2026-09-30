// Copyright (C) 2026 SHIXIN LAB / Shixin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
@preconcurrency import Sparkle

@MainActor
final class AppUpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var status = "尚未检查"
    @Published private(set) var latestVersion: String?
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecksEnabled = false
    @Published private(set) var isConfigured = false

    let currentVersion: String
    let currentBuild: String
    private let gate: UpdateActivityGate
    private let defaults: UserDefaults
    private var controller: SPUStandardUpdaterController?
    private static let lastCheckKey = "CunJiUpdateLastCheckDate"

    override convenience init() {
        self.init(bundle: .main, defaults: .standard, gate: .shared)
    }

    init(bundle: Bundle, defaults: UserDefaults, gate: UpdateActivityGate) {
        self.gate = gate
        self.defaults = defaults
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        currentBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        lastCheckDate = defaults.object(forKey: Self.lastCheckKey) as? Date
        super.init()

        // A development bundle without a release key must never claim to be up to date.
        guard Self.hasUpdateConfiguration(bundle.infoDictionary ?? [:]) else {
            status = "此构建尚未配置正式更新源与签名，请使用已发布的安装包。"
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        do {
            try controller.updater.start()
            isConfigured = true
        } catch {
            status = error.localizedDescription
            return
        }
        controller.updater.publisher(for: \.canCheckForUpdates)
            // Sparkle also enables this to bring an existing update window back to front.
            // Disabling it throughout a cycle would strand a hidden download/ready window.
            .combineLatest(gate.$activityCount)
            .map { available, count in available && count == 0 }
            .assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticChecksEnabled)
    }

    static func hasUpdateConfiguration(_ info: [String: Any]) -> Bool {
        guard let version = info["CFBundleShortVersionString"] as? String, !version.isEmpty,
              let build = info["CFBundleVersion"] as? String, UInt64(build) != nil,
              let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32,
              let feed = info["SUFeedURL"] as? String, let url = URL(string: feed) else { return false }
        #if SHIXIN_UPDATE_TESTING
        if url.scheme == "http", ["127.0.0.1", "localhost"].contains(url.host ?? "") { return true }
        #endif
        return url.scheme == "https" && url.host != nil
    }

    func checkForUpdates() {
        guard canCheck else { return }
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }


    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard gate.beginUpdate() else { throw busyError }
        status = "正在检查更新…"
        latestVersion = nil
        lastCheckDate = Date()
        defaults.set(lastCheckDate, forKey: Self.lastCheckKey)
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        // Also covers resumed update cycles; don't rely solely on the initial check.
        if !gate.updateInProgress, !gate.beginUpdate() { throw busyError }
        guard gate.activityCount == 0 else { throw busyError }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        latestVersion = "\(item.displayVersionString) · \(item.versionString)"
        status = "发现可用更新，请在更新窗口中继续。"
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let error = error as NSError
        if let item = error.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem {
            latestVersion = "\(item.displayVersionString) · \(item.versionString)"
        }
        let reason = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
        switch reason {
        case Int(SPUNoUpdateFoundReason.onLatestVersion.rawValue): status = "当前已是最新可用版本。"
        case Int(SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue): status = "本地构建比当前更新源中的版本更新，不会降级。"
        case Int(SPUNoUpdateFoundReason.systemIsTooOld.rawValue),
             Int(SPUNoUpdateFoundReason.systemIsTooNew.rawValue),
             Int(SPUNoUpdateFoundReason.hardwareDoesNotSupportARM64.rawValue):
            status = "更新源中的新版本不适用于当前系统或硬件。"
        default: status = "当前更新源未提供适用版本。"
        }
    }

    func userDidCancelDownload(_ updater: SPUUpdater) { status = "已取消更新。" }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        status = "正在下载更新，请在更新窗口查看进度或取消。"
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        status = "更新已准备好，请在更新窗口选择安装并重启。"
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        status = "正在安装更新并等待 App 退出。"
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        defer { gate.endUpdate() }
        if let error = error as NSError?, !(error.domain == SUSparkleErrorDomain && error.code == SUError.noUpdateError.rawValue) {
            status = Self.failureStatus(error)
        } else if status == "正在检查更新…" || status == "发现可用更新，请在更新窗口中继续。" {
            status = "已取消更新。"
        }
    }

    static func failureStatus(_ error: NSError) -> String {
        guard error.domain == SUSparkleErrorDomain else { return error.localizedDescription }
        switch error.code {
        case Int(SUError.appcastParseError.rawValue):
            return "更新清单无法解析或验证，请稍后重试。"
        case Int(SUError.signatureError.rawValue), Int(SUError.validationError.rawValue):
            return "更新包未通过真实性验证，已停止安装。"
        default:
            return error.localizedDescription
        }
    }

    private var busyError: NSError {
        NSError(domain: "CunJi.Update", code: 1, userInfo: [NSLocalizedDescriptionKey:
            L10n.t("当前任务尚未结束，请在检测、测速、保存或导出完成后再更新。")])
    }
}
