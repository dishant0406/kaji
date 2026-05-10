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
        .background(DroidTheme.secondaryBackground)
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
                    .droidFont(size: 11, weight: .medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(selected || hovered ? DroidTheme.fg : DroidTheme.fgMuted)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(selected || hovered ? DroidTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(selected ? DroidTheme.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .droidPointer()
        .help(document.path)
    }

    private var scopeBadge: some View {
        Text(document.scope.rawValue)
            .droidFont(size: 9, weight: .semibold)
            .foregroundStyle(DroidTheme.fgDim)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(DroidTheme.bg, in: Capsule())
    }
}
