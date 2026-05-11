import SwiftUI

struct BrowserConsolePanel: View {
    @Binding var command: String
    let entries: [BrowserConsoleEntry]
    let isRunning: Bool
    let onRun: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dev Console")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KajiTheme.fg)
                Spacer()
                IconButton(symbol: "play.fill", accessibilityLabel: "Run JavaScript", action: onRun)
                    .disabled(isRunning || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                IconButton(symbol: "xmark", accessibilityLabel: "Close console", action: onClose)
            }
            KajiTextArea(
                placeholder: "Type JavaScript and press Command-Enter",
                text: $command,
                minHeight: 44,
                maxHeight: 88,
                monospaced: true,
                onCommandEnter: onRun
            )
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if entries.isEmpty {
                            Text("Console output appears here")
                                .foregroundStyle(KajiTheme.fgDim)
                        }
                        ForEach(entries) { entry in
                            BrowserConsoleEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
                }
                .onChange(of: entries.count) { _, _ in
                    if let lastID = entries.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 190)
            .background(KajiTheme.bg, in: RoundedRectangle(cornerRadius: KajiShape.tileRadius))
            .overlay(RoundedRectangle(cornerRadius: KajiShape.tileRadius).stroke(KajiTheme.border))
        }
        .padding(12)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.panelRadius))
        .overlay(RoundedRectangle(cornerRadius: KajiShape.panelRadius).stroke(KajiTheme.border))
        .padding(12)
    }
}

private struct BrowserConsoleEntryRow: View {
    let entry: BrowserConsoleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("> " + entry.command)
                .foregroundStyle(KajiTheme.fg)
            Text(entry.isRunning ? "..." : entry.result)
                .foregroundStyle(entry.isRunning ? KajiTheme.fgDim : KajiTheme.fgMuted)
        }
    }
}
