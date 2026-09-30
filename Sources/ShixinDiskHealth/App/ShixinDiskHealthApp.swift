import AppKit
import SwiftUI

@main
struct ShixinDiskHealthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appLanguagePreference") private var selectedLanguageRawValue = AppLanguagePreference.system.rawValue
    @StateObject private var appState: DiskHealthAppState
    @StateObject private var speedTestState: SpeedTestAppState
    @StateObject private var updateService: AppUpdateService

    init() {
        ReviewIsolation.validateBeforeInitializingStores()
        AppLanguageController.applyStoredPreference()
        _appState = StateObject(wrappedValue: DiskHealthAppState())
        _speedTestState = StateObject(wrappedValue: SpeedTestAppState())
        _updateService = StateObject(wrappedValue: AppUpdateService())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(speedTestState)
                .environmentObject(updateService)
                .environment(\.locale, AppLanguagePreference.locale(for: selectedLanguageRawValue))
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 640)
                .task {
                    appDelegate.attach(appState, speedTestState)
                    appState.refreshHardwareProfile()
                    await appState.runInitialDetection()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1040, height: 1000)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L10n.t("检查更新…")) { updateService.checkForUpdates() }
                    .disabled(!updateService.canCheck)
            }
            CommandGroup(after: .newItem) {
                Button("立即检测") {
                    Task { await appState.runDetection() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("保存快照") {
                    appState.saveCurrentSnapshot()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!appState.canSaveCurrentSnapshot)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(speedTestState)
                .environmentObject(updateService)
                .environment(\.locale, AppLanguagePreference.locale(for: selectedLanguageRawValue))
                .frame(width: 620, height: 520)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var current: AppDelegate?
    private weak var diskState: DiskHealthAppState?
    private weak var speedState: SpeedTestAppState?
    private var isCompletingTermination = false
    private var isRestarting = false
    var terminationReply: (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }

    func attach(_ disk: DiskHealthAppState, _ speed: SpeedTestAppState) {
        diskState = disk
        speedState = speed
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        WindowSizeController.applyDefaultMainWindowSize()
    }

    private func cancelDiskTasks() {
        diskState?.cancelForAppTermination()
        if speedState?.isRunning == true { speedState?.stopSpeedTest() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isCompletingTermination else { return .terminateLater }
        let gate = UpdateActivityGate.shared
        gate.beginTermination()
        cancelDiskTasks()
        guard gate.activityCount > 0 else { return .terminateNow }
        isCompletingTermination = true
        Task { @MainActor in
            await gate.waitUntilIdle()
            terminationReply(true)
        }
        return .terminateLater
    }

    func restartAfterDiskTasksFinish() {
        let gate = UpdateActivityGate.shared
        guard !isRestarting, !gate.updateInProgress, !gate.isTerminating else { NSSound.beep(); return }
        isRestarting = true
        gate.beginTermination()
        cancelDiskTasks()
        Task { @MainActor in
            await gate.waitUntilIdle()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = true
            do {
                _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
                NSApp.terminate(nil)
            } catch {
                isRestarting = false
                gate.cancelTermination()
                NSSound.beep()
            }
        }
    }
}

enum WindowSizeController {
    private static let defaultContentSize = NSSize(width: 1040, height: 1000)

    @MainActor
    static func applyDefaultMainWindowSize() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let window = NSApplication.shared.windows.first(where: { window in
                window.isVisible && !(window is NSPanel)
            }) else {
                return
            }
            window.setContentSize(defaultContentSize)
            if let screen = window.screen ?? NSScreen.main {
                var frame = window.frame
                let visibleFrame = screen.visibleFrame
                frame.origin.x = visibleFrame.midX - frame.width / 2
                frame.origin.y = visibleFrame.midY - frame.height / 2
                window.setFrame(frame, display: true)
            }
        }
    }
}
