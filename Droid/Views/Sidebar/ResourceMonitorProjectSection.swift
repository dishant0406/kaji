import SwiftUI

struct ResourceMonitorProjectSection: View {
    let project: ResourceMonitorProjectSnapshot
    let onCloseTerminal: (ResourceMonitorTerminalSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(spacing: 6) {
                ForEach(project.terminals) { terminal in
                    ResourceMonitorTerminalRow(
                        terminal: terminal,
                        onClose: { onCloseTerminal(terminal) }
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(project.name)
                .droidFont(size: 12, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
                .lineLimit(1)

            Spacer(minLength: 8)

            ResourceMetricBadge(text: ResourceMonitorFormatting.cpu(project.cpuPercent))
            ResourceMetricBadge(text: ResourceMonitorFormatting.memory(project.memoryBytes))
        }
    }
}

private struct ResourceMonitorTerminalRow: View {
    let terminal: ResourceMonitorTerminalSnapshot
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(terminal.title)
                    .droidFont(size: 12, weight: .medium)
                    .foregroundStyle(DroidTheme.fg)
                    .lineLimit(1)

                Text(subtitle)
                    .droidFont(size: 10, design: .monospaced)
                    .foregroundStyle(DroidTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ResourceMetricBadge(text: ResourceMonitorFormatting.cpu(terminal.cpuPercent))
                ResourceMetricBadge(text: ResourceMonitorFormatting.memory(terminal.memoryBytes))
                closeButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.tileRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.tileRadius)
                .strokeBorder(DroidTheme.border.opacity(0.8), lineWidth: 1)
        )
    }

    private var subtitle: String {
        let process = terminal.processName ?? "waiting"
        let pid = terminal.pid.map { "pid \($0)" } ?? "pid --"
        let tty = terminal.ttyName?.split(separator: "/").last.map(String.init)
        let threads = terminal.threadCount.map { "\($0)t" }
        return [process, pid, tty, threads].compactMap(\.self).joined(separator: "  ")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            DroidIcon(systemName: "xmark", size: 9)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(DroidTheme.bg.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(DroidTheme.border.opacity(0.8), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(DroidTheme.fgMuted)
        .help("Close Terminal")
    }
}

enum ResourceMonitorFormatting {
    static func cpu(_ value: Double?) -> String {
        guard let value else { return "--% CPU" }
        return "\(Int(value.rounded()))% CPU"
    }

    static func memory(_ bytes: UInt64?) -> String {
        guard let bytes else { return "-- MEM" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
