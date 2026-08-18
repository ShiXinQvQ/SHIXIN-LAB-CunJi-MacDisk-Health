import AppKit
import ShixinDiskHealthCore
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case report = "当前报告"
    case externalDisk = "外盘检测"
    case history = "历史记录"
    case speedTest = "速度测试"
    case systemInfo = "本机配置"
    case settings = "设置关于"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .report: "internaldrive"
        case .externalDisk: "externaldrive.connected.to.line.below"
        case .history: "clock.arrow.circlepath"
        case .speedTest: "speedometer"
        case .systemInfo: "laptopcomputer.and.iphone"
        case .settings: "gearshape.fill"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: DiskHealthAppState
    @State private var selection: AppSection? = .report

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            ZStack {
                LabBackground()
                switch selection ?? .report {
                case .report:
                    CurrentReportView()
                case .externalDisk:
                    ExternalDiskView()
                case .history:
                    HistoryView()
                case .speedTest:
                    SpeedTestView()
                case .systemInfo:
                    SystemInfoView()
                case .settings:
                    SettingsView()
                }
            }
        }
        .accessibilityReduceMotionTransaction()
    }
}

struct SidebarView: View {
    @Binding var selection: AppSection?

    var body: some View {
        List(AppSection.allCases, selection: $selection) { section in
            Label(L10n.t(section.rawValue), systemImage: section.symbolName)
                .tag(section)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("SHIXIN LAB")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://shixinqvq.com/")!)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "globe")
                            Text("访问官网")
                        }
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                }
                Text("存迹 · MacDisk Health / Disk SMART")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

struct LabBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.04, blue: 0.06),
                Color(red: 0.05, green: 0.07, blue: 0.10),
                Color(red: 0.02, green: 0.025, blue: 0.035)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
