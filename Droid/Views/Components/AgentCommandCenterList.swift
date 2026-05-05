import SwiftUI

struct AgentCommandCenterList: View {
    let sections: [AgentCommandCenterSection]
    let highlightedEntryID: String?
    let highlightedIndex: Int?
    let entries: [AgentCommandCenterEntry]

    var body: some View {
        Group {
            if entries.isEmpty {
                VStack { Spacer()
                    emptyText
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                switch row.kind {
                                case let .section(section):
                                    AgentCommandCenterSectionHeader(section: section)
                                        .id(row.id)
                                case let .entry(entry):
                                    AgentCommandCenterRow(entry: entry, isHighlighted: entry.id == highlightedEntryID)
                                        .padding(.horizontal, 8)
                                        .id(row.id)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onChange(of: highlightedRowID) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var rows: [AgentCommandCenterListRow] {
        sections.flatMap { section in
            [AgentCommandCenterListRow(kind: .section(section))] + section.entries.map { entry in
                AgentCommandCenterListRow(kind: .entry(entry))
            }
        }
    }

    private var highlightedRowID: String? {
        guard let highlightedEntryID else { return nil }
        return rows.first { row in
            if case let .entry(entry) = row.kind {
                return entry.id == highlightedEntryID
            }
            return false
        }?.id
    }

    private var emptyText: some View {
        Text("No matching agent actions")
            .droidFont(size: 12)
            .foregroundStyle(DroidTheme.fgDim)
    }
}

private struct AgentCommandCenterListRow: Identifiable {
    let kind: Kind

    var id: String {
        switch kind {
        case let .section(section):
            "section-\(section.id)"
        case let .entry(entry):
            "entry-\(entry.id)"
        }
    }

    enum Kind {
        case section(AgentCommandCenterSection)
        case entry(AgentCommandCenterEntry)
    }
}
