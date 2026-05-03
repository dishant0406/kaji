import SwiftUI

struct ParentAgentQuestionPrompt: View {
    let question: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                DroidIcon(systemName: "questionmark.circle", size: 13)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .frame(width: 18, height: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Droid needs input")
                        .droidFont(size: 12, weight: .semibold)
                        .foregroundStyle(DroidTheme.fg)
                    MarkdownInlineText(content: question, size: 13, color: DroidTheme.fgMuted)
                }
                Spacer(minLength: 0)
            }

            Text("Reply below to continue")
                .droidFont(size: 11)
                .foregroundStyle(DroidTheme.fgDim)
                .padding(.leading, 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}
