import SwiftUI

struct KajiAgentApprovalBar: View {
    let request: KajiAgentApprovalRequest
    let onChoose: (KajiAgentApprovalOption) -> Void
    let onCancel: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded { detail }
            actions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(KajiTheme.borderStrong.opacity(0.65)))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            KajiIcon(systemName: "lock.shield", size: 13)
                .foregroundStyle(KajiTheme.diffHunkFg)
                .frame(width: 18, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(request.title)
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text(request.toolName)
                    .kajiFont(size: 12, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(expanded ? "Hide" : "Details") { expanded.toggle() }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
        }
    }

    private var detail: some View {
        Text(request.summary)
            .kajiFont(size: 12, design: .monospaced)
            .foregroundStyle(KajiTheme.fgMuted)
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KajiTheme.bg.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            ForEach(request.options) { option in
                Button(option.title) { onChoose(option) }
                    .buttonStyle(KajiButtonStyle(option.isAllow ? .primary : .secondary, size: .small))
            }
            Button("Cancel") { onCancel() }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            Spacer(minLength: 0)
        }
        .padding(.leading, 28)
    }
}
