import SwiftUI

struct ParentAgentQuestionPrompt: View {
    let pendingQuestion: ParentAgentPendingQuestion
    let onSelect: (ParentAgentQuestionOption) -> Void
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                KajiIcon(systemName: "questionmark.circle", size: 13)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .frame(width: 18, height: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kaji needs input")
                        .kajiFont(size: 12, weight: .semibold)
                        .foregroundStyle(KajiTheme.fg)
                    MarkdownInlineText(content: pendingQuestion.question, size: 13, color: KajiTheme.fgMuted)
                }
                Spacer(minLength: 0)
            }

            if pendingQuestion.options.isEmpty {
                Text("Reply below to continue")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
                    .padding(.leading, 28)
            } else {
                optionPicker
                    .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: pendingQuestion.toolID) { filter = "" }
    }

    private var optionPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchField
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filteredOptions.enumerated()), id: \.element.id) { index, option in
                        optionButton(option, index: index)
                        if option.id != filteredOptions.last?.id {
                            Rectangle()
                                .fill(KajiTheme.border.opacity(0.5))
                                .frame(height: 1)
                                .padding(.leading, 34)
                        }
                    }
                }
            }
            .frame(height: optionListHeight)
            .background(KajiTheme.bg.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
            resultCount
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "magnifyingglass", size: 11)
                .foregroundStyle(KajiTheme.fgDim)
            TextField("Search options", text: $filter)
                .textFieldStyle(.plain)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fg)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(KajiTheme.bg.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }

    private func optionButton(_ option: ParentAgentQuestionOption, index: Int) -> some View {
        Button {
            onSelect(option)
        } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .kajiFont(size: 11, weight: .medium)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .frame(width: 24, height: 24)
                    .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .kajiFont(size: 12, weight: .semibold)
                        .foregroundStyle(KajiTheme.fg)
                    if let detail = option.detail, !detail.isEmpty {
                        Text(detail)
                            .kajiFont(size: 11)
                            .foregroundStyle(KajiTheme.fgDim)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                KajiIcon(systemName: "arrow.right", size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
    }

    private var resultCount: some View {
        Text(resultCountText)
            .kajiFont(size: 11)
            .foregroundStyle(KajiTheme.fgDim)
    }

    private var resultCountText: String {
        if filteredOptions.isEmpty {
            return "No matching options"
        }
        if filteredOptions.count > 12 {
            return "\(filteredOptions.count) matches. Scroll or keep typing to narrow results."
        }
        return "\(filteredOptions.count) option\(filteredOptions.count == 1 ? "" : "s")"
    }

    private var optionListHeight: CGFloat {
        guard !filteredOptions.isEmpty else { return 48 }
        let rowHeight: CGFloat = 56
        return min(CGFloat(filteredOptions.count) * rowHeight, 340)
    }

    private var filteredOptions: [ParentAgentQuestionOption] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return pendingQuestion.options }
        return pendingQuestion.options.filter { option in
            option.title.lowercased().contains(query) ||
                option.detail?.lowercased().contains(query) == true
        }
    }
}
