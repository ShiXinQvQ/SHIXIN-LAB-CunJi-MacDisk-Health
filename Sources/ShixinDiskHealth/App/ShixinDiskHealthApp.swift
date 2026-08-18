import AppKit
import SwiftUI

@main
struct ShixinDiskHealthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appLanguagePreference") private var selectedLanguageRawValue = AppLanguagePreference.system.rawValue
    @StateObject private var appState = DiskHealthAppState()
    @StateObject private var speedTestState = SpeedTestAppState()

    init() {
        AppLanguageController.applyStoredPreference()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(speedTestState)
                .environment(\.locale, AppLanguagePreference.locale(for: selectedLanguageRawValue))
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 640)
                .task {
                    appState.refreshHardwareProfile()
                    await appState.runInitialDetection()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1040, height: 1000)
        .commands {
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
                .environment(\.locale, AppLanguagePreference.locale(for: selectedLanguageRawValue))
                .frame(width: 620, height: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowSizeController.applyDefaultMainWindowSize()
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
