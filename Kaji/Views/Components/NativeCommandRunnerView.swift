import AppKit
import SwiftUI

struct NativeCommandRunnerView: View {
    let runner: NativeCommandRunner
    let onStop: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(KajiTheme.border.opacity(0.75))
            outputView
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: statusIcon, size: 13)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(runner.plan?.title ?? "Command")
                    .kajiFont(size: 13, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                Text(statusText)
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
                    .lineLimit(1)
            }
            Spacer()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(runner.output, forType: .string)
            }
            .buttonStyle(.plain)
            .foregroundStyle(KajiTheme.fgMuted)
            if runner.isRunning {
                Button("Stop", action: onStop)
                    .buttonStyle(.plain)
                    .foregroundStyle(KajiTheme.diffRemoveFg)
            } else {
                Button("Close", action: onClose)
                    .buttonStyle(.plain)
                    .foregroundStyle(KajiTheme.fgMuted)
            }
        }
        .padding(14)
    }

    private var outputView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                Text(outputText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(KajiTheme.fgMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
                    .id("output")
            }
            .background(KajiTheme.surface.opacity(0.45))
            .onChange(of: runner.output) { _, _ in
                proxy.scrollTo("output", anchor: .bottom)
            }
        }
    }

    private var outputText: String {
        runner.output.isEmpty ? "$ \(runner.plan?.title ?? "command")" : runner.output
    }

    private var statusText: String {
        switch runner.status {
        case .idle:
            "Ready"
        case .running:
            "Running in \(runner.plan?.workingDirectory.path ?? "")"
        case .succeeded:
            "Completed"
        case let .failed(code):
            "Failed with exit code \(code)"
        }
    }

    private var statusIcon: String {
        switch runner.status {
        case .idle:
            "terminal"
        case .running:
            "play"
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
