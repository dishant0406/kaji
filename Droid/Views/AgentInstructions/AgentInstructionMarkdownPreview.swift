import SwiftUI

struct AgentInstructionMarkdownPreview: View {
    let document: AgentInstructionDocument?

    var body: some View {
        if let document {
            NativeMarkdownView(content: document.content, filePath: document.path)
                .background(DroidTheme.bg)
        } else {
            VStack(spacing: 8) {
                DroidIcon(systemName: "doc.text", size: 22)
                    .foregroundStyle(DroidTheme.fgDim)
                Text("Select an instruction file")
                    .droidFont(size: 13, weight: .medium)
                    .foregroundStyle(DroidTheme.fgMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DroidTheme.bg)
        }
    }
}
