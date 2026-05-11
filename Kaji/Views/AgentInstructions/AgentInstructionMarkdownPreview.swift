import SwiftUI

struct AgentInstructionMarkdownPreview: View {
    let document: AgentInstructionDocument?

    var body: some View {
        if let document {
            NativeMarkdownView(content: document.content, filePath: document.path)
                .background(KajiTheme.bg)
        } else {
            VStack(spacing: 8) {
                KajiIcon(systemName: "doc.text", size: 22)
                    .foregroundStyle(KajiTheme.fgDim)
                Text("Select an instruction file")
                    .kajiFont(size: 13, weight: .medium)
                    .foregroundStyle(KajiTheme.fgMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KajiTheme.bg)
        }
    }
}
