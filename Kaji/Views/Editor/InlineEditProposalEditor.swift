import SwiftUI

struct InlineEditProposalEditor: View {
    @Binding var proposal: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Proposed Replacement")
                    .kajiFont(size: 11, weight: .semibold)
                    .foregroundStyle(KajiTheme.fgMuted)
                Spacer()
                Text(metadata)
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            TextEditor(text: $proposal)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .foregroundStyle(KajiTheme.fg)
                .padding(8)
                .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
    }

    private var metadata: String {
        let lineCount = proposal.components(separatedBy: .newlines).count
        return "\(lineCount) lines • \(proposal.count) chars"
    }
}
