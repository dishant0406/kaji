import Pow
import SwiftUI

struct KajiKitScriptRunnerView: View {
    let runner: KajiKitScriptRunner
    let onStop: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(KajiTheme.border.opacity(0.75))
            outputView
        }
        .onChange(of: runner.status) { _, status in
            guard case .succeeded = status, runner.plan?.script.autoCloseOnSuccess == true else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1200))
                onClose()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: statusIcon, size: 13)
                .foregroundStyle(statusColor)
                .kajiChangeFeedback(statusFeedback, value: statusText)
            VStack(alignment: .leading, spacing: 2) {
                Text(runner.plan?.script.title ?? "Running script")
                    .kajiFont(size: 13, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text(statusText)
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer()
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
                Text(runner.output.isEmpty ? "$ \(runner.plan?.script.slug ?? "script")" : runner.output)
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

    private var statusText: String {
        switch runner.status {
        case .idle: "Ready"
        case .running: "Running in \(runner.plan?.workingDirectory.path ?? "")"
        case .succeeded: "Completed. Closing..."
        case let .failed(code): "Failed with exit code \(code)"
        }
    }

    private var statusIcon: String {
        switch runner.status {
        case .idle: "terminal"
        case .running: "play"
        case .succeeded: "checkmark"
        case .failed: "xmark"
        }
    }

    private var statusColor: Color {
        switch runner.status {
        case .failed: KajiTheme.diffRemoveFg
        case .succeeded: KajiTheme.diffAddFg
        default: KajiTheme.fgMuted
        }
    }

    private var statusFeedback: AnyChangeEffect {
        switch runner.status {
        case .failed:
            KajiMotion.invalidFeedback
        case .succeeded:
            KajiMotion.successFeedback
        default:
            KajiMotion.tapFeedback
        }
    }
}
