import SwiftUI

struct AgentCommandCenterList: View {
    let sections: [AgentCommandCenterSection]
    let highlightedEntryID: String?
    let highlightedIndex: Int?
    let entries: [AgentCommandCenterEntry]

    var body: some View {
        Group {
            if entries.isEmpty {
                VStack { Spacer(); emptyText; Spacer() }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(sections) { section in
                                AgentCommandCenterSectionHeader(section: section)
                                ForEach(section.entries) { entry in
                                    AgentCommandCenterRow(entry: entry, isHighlighted: entry.id == highlightedEntryID)
                                        .padding(.horizontal, 8)
                                        .id(entry.id)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onChange(of: highlightedIndex) { _, index in
                        guard let index, index < entries.count else { return }
                        proxy.scrollTo(entries[index].id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyText: some View {
        Text("No matching agent actions")
            .droidFont(size: 12)
            .foregroundStyle(DroidTheme.fgDim)
    }
}
