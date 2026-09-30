// Copyright (C) 2026 SHIXIN LAB / Shixin
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct UpdateSettingsCard: View {
    @EnvironmentObject private var service: AppUpdateService
    @ObservedObject private var gate = UpdateActivityGate.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "软件更新", systemImage: "arrow.triangle.2.circlepath")
            KeyValueRow(title: "当前版本", value: "\(service.currentVersion) · \(service.currentBuild)")
            KeyValueRow(title: "更新源版本", value: service.latestVersion ?? L10n.t(service.lastCheckDate == nil ? "尚未检查" : "未取得版本信息"))
            KeyValueRow(title: "上次检查", value: service.lastCheckDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            Text(L10n.t(service.status))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if gate.activityCount > 0 {
                Text(L10n.t("当前任务尚未结束，请在检测、测速、保存或导出完成后再更新。"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button(L10n.t("检查更新…")) { service.checkForUpdates() }
                .buttonStyle(.bordered)
                .disabled(!service.canCheck)
            Toggle(L10n.t("自动检查更新"), isOn: Binding(
                get: { service.automaticChecksEnabled },
                set: { service.setAutomaticChecks($0) }
            ))
            .disabled(!service.isConfigured)
            Text(L10n.t("默认关闭。开启后约每日检查一次；下载和安装仍由你决定。检查会连接更新服务器，不上传硬盘信息或历史记录。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .settingsCard()
    }
}
