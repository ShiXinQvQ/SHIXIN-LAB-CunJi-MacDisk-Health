import ShixinDiskHealthCore
import SwiftUI

struct SystemInfoView: View {
    @EnvironmentObject private var appState: DiskHealthAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SystemInfoHeader()
                SystemHeadlineGrid(profile: appState.hardwareProfile)
                SystemDetailSectionsView(sections: appState.hardwareProfile.sections)
                if let message = appState.hardwareProfile.message {
                    HardwareWarningCard(title: "本机配置读取提示", message: message, tint: .orange)
                }
            }
            .padding(22)
        }
    }
}

struct SystemInfoHeader: View {
    @EnvironmentObject private var appState: DiskHealthAppState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                titleBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    appState.refreshHardwareProfile()
                } label: {
                    Label("刷新配置", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            VStack(alignment: .leading, spacing: 14) {
                titleBlock
                Button {
                    appState.refreshHardwareProfile()
                } label: {
                    Label("刷新配置", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .labGlassCard(padding: 16, cornerRadius: 18)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("本机配置")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            Text("系统、芯片、图形、内存、存储与设备标识概览")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }
}

struct SystemHeadlineGrid: View {
    var profile: HardwareProfile

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(profile.headlineRows.prefix(4)) { row in
                HardwareMetricTile(row: row, tint: tint(for: row.systemImage), compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func tint(for systemImage: String) -> Color {
        switch systemImage {
        case "cpu": .green
        case "rectangle.3.group": .blue
        case "memorychip": .purple
        default: .cyan
        }
    }
}

struct HardwareInfoSectionCard: View {
    var section: HardwareInfoSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: section.title, systemImage: section.systemImage)
            ForEach(section.rows) { row in
                HardwareInfoRowView(row: row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .labGlassCard()
    }
}

struct SystemDetailSectionsView: View {
    var sections: [HardwareInfoSection]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            detailColumn(leftSections)
            detailColumn(rightSections)
        }
    }

    private var leftSections: [HardwareInfoSection] {
        orderedSections(names: [
            "系统软件信息",
            "处理器与内存",
            "隐私与设备标识"
        ])
    }

    private var rightSections: [HardwareInfoSection] {
        orderedSections(names: [
            "系统硬件信息",
            "图形与显示",
            "内置存储"
        ])
    }

    private func orderedSections(names: [String]) -> [HardwareInfoSection] {
        names.compactMap { name in
            guard let section = sections.first(where: { $0.title == name }) else { return nil }
            return section
        }
    }

    private func detailColumn(_ sections: [HardwareInfoSection]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sections) { section in
                HardwareInfoSectionCard(section: section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct HardwareMetricTile: View {
    var row: HardwareInfoRow
    var tint: Color
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack {
                Image(systemName: row.systemImage)
                    .font(compact ? .headline : .title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(L10n.t(row.value))
                .font(.system(size: compact ? 24 : 28, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(compact ? 0.5 : 0.62)
                .frame(height: compact ? 31 : 38, alignment: .bottomLeading)
            VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(L10n.t(row.title))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    InfoHelpButton(title: row.title, message: row.help)
                }
                if let detail = row.detail, !detail.isEmpty {
                    Text(L10n.t(detail))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(compact ? 0.64 : 0.72)
                        .truncationMode(.tail)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 100 : 108, alignment: .topLeading)
        .labGlassCard(padding: compact ? 13 : 15, cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }
}

struct HardwareInfoRowView: View {
    var row: HardwareInfoRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(L10n.t(row.title))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                InfoHelpButton(title: row.title, message: row.help)
            }
            Spacer(minLength: 18)
            VStack(alignment: .trailing, spacing: 2) {
                Text(L10n.t(row.value))
                    .font(isMonospaced ? .body.monospaced() : .body)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let detail = row.detail, !detail.isEmpty {
                    Text(L10n.t(detail))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .font(.callout)
        .padding(.vertical, 5)
    }

    private var isMonospaced: Bool {
        row.value.contains(".") || row.value.contains(",") || row.value.contains("/") || row.value.contains("-")
    }
}

struct HardwareWarningCard: View {
    var title: String
    var message: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.t(title))
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .labGlassCard()
    }
}
