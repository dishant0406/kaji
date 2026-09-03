import AppKit
import Pow
import SwiftUI

struct NativeCommandRunnerView: View {
    let runner: NativeCommandRunner
    let onStop: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(KajiTheme.border.opacity(0.75))
            commandSummary
            Divider().overlay(KajiTheme.border.opacity(0.55))
            outputView
        }
        .background(KajiTheme.bg)
    }

    private var header: some View {
        HStack(spacing: 12) {
            statusBadge
            VStack(alignment: .leading, spacing: 2) {
                Text("Command Run")
                    .kajiFont(size: 13, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                Text(statusText)
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
                    .lineLimit(1)
            }
            Spacer()
            IconButton(symbol: "doc.on.doc", accessibilityLabel: "Copy Command Output", action: copyOutput)
                .help("Copy output")
            if runner.isRunning {
                IconButton(
                    symbol: "stop.fill",
                    color: KajiTheme.diffRemoveFg,
                    hoverColor: KajiTheme.diffRemoveFg,
                    accessibilityLabel: "Stop Command",
                    action: onStop
                )
                .help("Stop command")
            } else {
                IconButton(symbol: "xmark", accessibilityLabel: "Close Command Output", action: onClose)
                    .help("Close")
            }
        }
        .padding(14)
    }

    private var statusBadge: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.14))
            KajiIcon(systemName: statusIcon, size: 13)
                .foregroundStyle(statusColor)
        }
        .frame(width: 30, height: 30)
        .overlay(Circle().stroke(statusColor.opacity(0.24), lineWidth: 1))
        .kajiChangeFeedback(runner.isRunning ? KajiMotion.tapFeedback : completionFeedback, value: statusText)
    }

    private var completionFeedback: AnyChangeEffect {
        if case .succeeded = runner.status {
            return KajiMotion.successFeedback
        }
        return KajiMotion.invalidFeedback
    }

    private var commandSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow(label: "Command", value: runner.plan?.title ?? "command", icon: "chevron.right")
            summaryRow(label: "Workspace", value: workingDirectoryText, icon: "folder")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(KajiTheme.secondaryBackground.opacity(0.55))
    }

    private var outputView: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                outputHeader
                ScrollView(.vertical, showsIndicators: true) {
                    Text(outputText)
                        .kajiFont(size: 12, design: .monospaced)
                        .foregroundStyle(outputColor)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .id("output")
                }
                .background(KajiTheme.bg)
            }
            .onChange(of: runner.output) { _, _ in
                proxy.scrollTo("output", anchor: .bottom)
            }
        }
    }

    private var outputHeader: some View {
        HStack(spacing: 8) {
            Text("Output")
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fg)
            if runner.output.isEmpty {
                Text("waiting")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            } else {
                Text("\(outputLineCount) lines")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(KajiTheme.secondaryBackground.opacity(0.38))
        .overlay(alignment: .bottom) {
            Rectangle().fill(KajiTheme.border.opacity(0.55)).frame(height: 1)
        }
    }

    private var outputText: String {
        runner.output.isEmpty ? "No output yet." : runner.output
    }

    private var outputColor: Color {
        runner.output.isEmpty ? KajiTheme.fgDim : KajiTheme.fgMuted
    }

    private var outputLineCount: Int {
        max(1, runner.output.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    private var workingDirectoryText: String {
        runner.plan?.workingDirectory.path ?? ""
    }

    private func summaryRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: icon, size: 11)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(width: 14)
            Text(label)
                .kajiFont(size: 11, weight: .medium)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .kajiFont(size: 12, design: label == "Command" ? .monospaced : .default)
                .foregroundStyle(KajiTheme.fg)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(runner.output, forType: .string)
    }

    private var statusText: String {
        switch runner.status {
        case .idle:
            "Ready"
        case .running:
            "Running in the active workspace"
        case .succeeded:
            "Completed"
        case let .failed(code):
            "Failed with exit code \(code)"
        }
    }

    private var statusIcon: String {
        switch runner.status {
        case .idle:
            "command"
        case .running:
            "play.fill"
        case .succeeded:
            "checkmark"
        case .failed:
            "xmark"
        }
    }

    private var statusColor: Color {
        switch runner.status {
        case .failed:
            KajiTheme.diffRemoveFg
        case .succeeded:
            KajiTheme.diffAddFg
        default:
            KajiTheme.fgMuted
        }
    }
}
