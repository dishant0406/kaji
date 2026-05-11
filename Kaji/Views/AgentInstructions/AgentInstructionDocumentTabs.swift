import SwiftUI

struct AgentInstructionDocumentTabs: View {
    let documents: [AgentInstructionDocument]
    let selectedDocumentID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(documents) { document in
                    AgentInstructionDocumentTab(
                        document: document,
                        selected: document.id == selectedDocumentID
                    ) {
                        onSelect(document.id)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .background(KajiTheme.secondaryBackground)
    }
}

private struct AgentInstructionDocumentTab: View {
    let document: AgentInstructionDocument
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                scopeBadge
                Text(document.displayPath)
                    .kajiFont(size: 11, weight: .medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(selected || hovered ? KajiTheme.fg : KajiTheme.fgMuted)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(selected || hovered ? KajiTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(selected ? KajiTheme.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .kajiPointer()
        .help(document.path)
    }

    private var scopeBadge: some View {
        Text(document.scope.rawValue)
            .kajiFont(size: 9, weight: .semibold)
            .foregroundStyle(KajiTheme.fgDim)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(KajiTheme.bg, in: Capsule())
    }
}
