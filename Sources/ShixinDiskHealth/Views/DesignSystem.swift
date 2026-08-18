import AppKit
import ShixinDiskHealthCore
import SwiftUI

extension View {
    @ViewBuilder
    func labGlassCard(padding: CGFloat = 18, cornerRadius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
#if canImport(SwiftUI, _version: 7.0)
        if #available(macOS 26.0, *) {
            self
                .padding(padding)
                .background {
                    shape.fill(Color.white.opacity(0.035))
                }
                .glassEffect(.regular.tint(Color.white.opacity(0.04)), in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.12), lineWidth: 1)
                }
        } else {
            self
                .padding(padding)
                .background(.thinMaterial, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.08), lineWidth: 1)
                }
        }
#else
        self
            .padding(padding)
            .background(.thinMaterial, in: shape)
            .overlay {
                shape.stroke(.white.opacity(0.08), lineWidth: 1)
            }
#endif
    }

    func accessibilityReduceMotionTransaction() -> some View {
        transaction { transaction in
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                transaction.animation = nil
            }
        }
    }
}

extension HealthLevel {
    var accentColor: Color {
        switch self {
        case .healthy: Color(red: 0.23, green: 0.82, blue: 0.55)
        case .attention: Color(red: 1.0, green: 0.72, blue: 0.24)
        case .risk: Color(red: 1.0, green: 0.32, blue: 0.32)
        case .unknown: Color.secondary
        }
    }
}

extension ReadCompleteness {
    var accentColor: Color {
        switch self {
        case .complete: .green
        case .coreCompleteSupplementalUnavailable: .blue
        case .coreMissing: .orange
        case .failed: .red
        }
    }
}

extension DiskConnectionKind {
    var tint: Color {
        switch self {
        case .internalPhysical: .blue
        case .externalPhysical: Color(red: 0.74, green: 0.32, blue: 0.82)
        case .networkVolume: .teal
        case .unknown: .gray
        }
    }
}

struct SectionHeader: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(L10n.t(title))
                .font(.headline)
                .lineLimit(1)
            Spacer()
        }
    }
}

struct StatusPill: View {
    var text: String
    var systemImage: String
    var tint: Color
    var width: CGFloat? = nil

    var body: some View {
        Label(L10n.t(text), systemImage: systemImage)
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay {
                Capsule().stroke(tint.opacity(0.22), lineWidth: 1)
            }
    }
}

struct InfoHelpButton: View {
    var title: String
    var message: String
    @State private var isPresented = false
    @State private var isPinned = false
    @State private var hoverToken = UUID()

    var body: some View {
        Button {
            isPinned.toggle()
            isPresented = isPinned
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        .buttonStyle(.plain)
        .help(L10n.t(title))
        .onHover { hovering in
            updateHoverState(hovering)
        }
        .onChange(of: isPresented) { _, presented in
            if !presented {
                isPinned = false
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t(title))
                    .font(.headline)
                Text(L10n.t(message))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 320, alignment: .leading)
        }
        .accessibilityLabel(L10n.t(title))
        .accessibilityHint(L10n.t(message))
    }

    private func updateHoverState(_ hovering: Bool) {
        hoverToken = UUID()
        let token = hoverToken
        let delay: TimeInterval = hovering ? 0.18 : 0.28
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard hoverToken == token else { return }
            if hovering {
                isPresented = true
            } else if !isPinned {
                isPresented = false
            }
        }
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var detail: String?
    var systemImage: String
    var tint: Color = .white
    var help: String?
    var usesProminentTitle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(L10n.t(value))
                .font(.system(size: 28, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(L10n.t(title))
                        .font(usesProminentTitle ? .system(size: 14, weight: .medium) : .subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    if let help, !help.isEmpty {
                        InfoHelpButton(title: title, message: help)
                    }
                }
                if let detail, !detail.isEmpty {
                    Text(L10n.t(detail))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .labGlassCard(padding: 15, cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }
}

struct KeyValueRow: View {
    var title: String
    var value: String
    var monospaced = false
    var helpTitle: String?
    var help: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(L10n.t(title))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let helpTitle, let help {
                    InfoHelpButton(title: helpTitle, message: help)
                }
            }
            Spacer(minLength: 18)
            Text(L10n.t(value))
                .font(monospaced ? .body.monospaced() : .body)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
        .padding(.vertical, 5)
    }
}

struct CopyablePathRow: View {
    var title: String
    var value: String
    var helpTitle: String?
    var help: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(L10n.t(title))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let helpTitle, let help {
                    InfoHelpButton(title: helpTitle, message: help)
                }
            }
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("复制路径"))
        }
        .font(.callout)
        .padding(.vertical, 5)
    }
}
