import AppKit
import ShixinDiskHealthCore
import SwiftUI

private extension View {
    func settingsCard(padding: CGFloat = 18, cornerRadius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .padding(padding)
            .background {
                shape.fill(Color(red: 0.135, green: 0.145, blue: 0.155))
            }
            .overlay {
                shape.stroke(.white.opacity(0.12), lineWidth: 1)
            }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: DiskHealthAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PrivacySettingsCard()
                LanguageSettingsCard()
                SmartctlSourceCard()
                AdvancedHelperCard()
                AboutCard()
            }
            .padding(22)
        }
        .background(LabBackground())
    }
}

struct LanguageSettingsCard: View {
    @AppStorage("appLanguagePreference") private var selectedRawValue = AppLanguagePreference.system.rawValue
    @State private var showsRestartHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "语言", systemImage: "globe")
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("界面语言")
                        .font(.callout.weight(.medium))
                    Text("默认跟随 macOS 当前语言。更改后点击下方按钮重启 App 生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("界面语言", selection: $selectedRawValue) {
                    ForEach(AppLanguagePreference.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            if showsRestartHint {
                Button {
                    AppRestarter.restartApp()
                } label: {
                    Label(L10n.t("重启并应用语言"), systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .settingsCard()
        .onChange(of: selectedRawValue) { _, newValue in
            applyLanguagePreference(newValue)
            showsRestartHint = true
        }
    }

    private func applyLanguagePreference(_ rawValue: String) {
        let preference = AppLanguagePreference(rawValue: rawValue) ?? .system
        AppLanguageController.apply(preference)
    }
}

struct PrivacySettingsCard: View {
    @EnvironmentObject private var appState: DiskHealthAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "隐私与显示", systemImage: "lock.shield")
            Toggle("显示完整序列号", isOn: $appState.showSerialNumber)
            Toggle("显示完整设备标识", isOn: showPrivateIdentifiersBinding)
            Text("为保护隐私，序列号、Provisioning UDID、平台 UUID 等可识别设备的信息默认隐藏，仅在你主动开启后于本机界面显示。历史快照会在本机保存完整序列号，导出 JSON / CSV 前会再次提醒可能包含设备信息；分享截图、日志或导出文件前，请确认显示设置并检查内容。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .settingsCard()
    }

    private var showPrivateIdentifiersBinding: Binding<Bool> {
        Binding {
            appState.showPrivateHardwareIdentifiers
        } set: { newValue in
            appState.setShowPrivateHardwareIdentifiers(newValue)
        }
    }
}

struct SmartctlSourceCard: View {
    @EnvironmentObject private var appState: DiskHealthAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "smartctl 与读取来源", systemImage: "terminal")
            KeyValueRow(title: "当前实际来源", value: appState.currentSnapshotForSelectedDisk?.readMode.rawValue ?? "尚未检测")
            if let path = appState.currentSnapshotForSelectedDisk?.smartctlPath {
                CopyablePathRow(title: "当前路径", value: path)
            }
            KeyValueRow(title: "App 内置 smartctl", value: bundledSmartctlState)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("手动路径只用于非 helper fallback。正式 privileged helper 不会以 root 身份执行用户手动选择的任意路径。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("可选：手动选择 smartctl 路径", text: $appState.manualSmartctlPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit { appState.persistManualPath() }
                        Button("选择") {
                            appState.chooseManualSmartctlPath()
                        }
                        Button("保存") {
                            appState.persistManualPath()
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("高级：手动 smartctl 路径")
            }
        }
        .settingsCard()
    }

    private var bundledSmartctlState: String {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Tools/smartctl"),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return "可用"
        }
        return "未内置或不可执行"
    }
}

struct AdvancedHelperCard: View {
    @EnvironmentObject private var appState: DiskHealthAppState
    @State private var showsHelperInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "key.radiowaves.forward")
                        .foregroundStyle(.secondary)
                    Text("高级权限")
                        .font(.headline)
                        .lineLimit(1)
                    Button {
                        showsHelperInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("了解 Helper"))
                    .accessibilityLabel(L10n.t("了解 Helper"))
                    .popover(isPresented: $showsHelperInfo, arrowEdge: .top) {
                        Text("如后续版本启用 Helper，将同时提供 Developer ID 签名、公证以及完整的安装与卸载流程；当前版本不会安装或注册 Helper 服务。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(width: 360, alignment: .leading)
                    }
                }
                Spacer(minLength: 12)
                StatusPill(text: "正式 Helper 暂未开放安装", systemImage: "info.circle.fill", tint: .blue)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text("当前版本通过 direct mode 读取核心 SMART / NVMe 数据；Helper 仅作为可选的增强权限通道，不影响当前检测功能。")
                .font(.callout)
                .foregroundStyle(.secondary)
            KeyValueRow(title: "Helper 状态", value: "当前无需安装")
            HStack {
                Button {
                } label: {
                    Label("注册 Helper", systemImage: "plus.circle")
                }
                .disabled(true)
                Button {
                } label: {
                    Label("取消注册", systemImage: "minus.circle")
                }
                .disabled(true)
            }
        }
        .settingsCard()
    }
}

struct AboutCard: View {
    @EnvironmentObject private var appState: DiskHealthAppState
    @EnvironmentObject private var speedTestState: SpeedTestAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "关于", systemImage: "info.circle")
            HStack(alignment: .center, spacing: 16) {
                AppIconPreview()

                VStack(alignment: .leading, spacing: 5) {
                    Text(appDisplayName)
                        .font(.title3.weight(.semibold))
                    Text("Mac SSD SMART / NVMe 健康控制台")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://shixinqvq.com/")!)
                    } label: {
                        Label("访问 SHIXIN LAB 官网", systemImage: "globe")
                    }
                    .buttonStyle(.link)
                }
            }

            KeyValueRow(title: "Bundle ID", value: bundleIdentifier, monospaced: true)
            KeyValueRow(title: "版本", value: versionText)
            KeyValueRow(title: "数据命名空间", value: AppRuntimeConfiguration.appSupportDirectoryName)
            CopyablePathRow(title: "SMART 历史位置", value: appState.store.snapshotsURL.path)
            CopyablePathRow(title: "速度测试历史", value: speedTestState.store.resultsURL.path)

            Divider().opacity(0.25)

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "开源组件", systemImage: "shippingbox")
                KeyValueRow(title: "组件", value: "smartmontools / smartctl")
                KeyValueRow(title: "当前捆绑版本", value: bundledVersion)
                KeyValueRow(title: "项目来源", value: "https://www.smartmontools.org/")
                KeyValueRow(title: "许可证", value: "GNU GPL")
                HStack {
                    Button("查看许可证") {
                        openResource("Licenses/smartmontools-COPYING.txt")
                    }
                    Button("查看 NOTICE") {
                        openResource("Licenses/smartmontools-NOTICE.md")
                    }
                    Button("查看 README") {
                        openResource("Licenses/smartmontools-README.txt")
                    }
                }
                Text("App 部分功能内置 smartmontools / smartctl，开源组件来源与 GPL 许可边界清晰。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsCard()
    }

    private var bundledVersion: String {
        (appState.currentSnapshotForSelectedDisk ?? appState.externalCurrentSnapshotForSelectedDisk)?
            .smartctlVersion.map { "smartctl \($0)" } ?? "smartctl 7.5（打包资源）"
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.shixinqvq.shixinlab.diskhealth"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
        return "v\(version)"
    }

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "SHIXIN LAB · 「存迹」"
    }

    private func openResource(_ relativePath: String) {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(relativePath)
        ].compactMap { $0 }
        if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct AppIconPreview: View {
    private static let displaySize: CGFloat = 80

    var body: some View {
        Group {
            if let image = Self.loadPreviewImage() {
                Image(nsImage: image)
                    .interpolation(.high)
                    .antialiased(true)
                    .accessibilityLabel("SHIXIN LAB · 存迹 MacDisk Health 图标")
            } else {
                Image(systemName: "internaldrive")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("App 图标")
            }
        }
        .frame(width: Self.displaySize, height: Self.displaySize)
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }

    private static func loadPreviewImage() -> NSImage? {
        let candidates = [
            Bundle.main.url(forResource: "AppIconPreviewInApp", withExtension: "png"),
            Bundle.main.url(forResource: "AppIconPreview", withExtension: "png")
        ].compactMap { $0 }

        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: displaySize, height: displaySize)
        return image
    }
}
