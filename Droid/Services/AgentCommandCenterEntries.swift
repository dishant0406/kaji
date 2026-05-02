import Foundation

@MainActor enum AgentCommandCenterEntries {
    private struct EntryTemplate {
        let category: String
        let title: String
        let detail: String
        let shortcut: String
        let action: AgentCommandCenterAction
    }

    static func entries(for items: [AgentMissionControlItem]) -> [AgentCommandCenterEntry] {
        items.flatMap(entries)
    }

    static func sections(for entries: [AgentCommandCenterEntry]) -> [AgentCommandCenterSection] {
        var sections: [AgentCommandCenterSection] = []
        for entry in entries {
            if let index = sections.firstIndex(where: { $0.id == entry.item.id }) {
                let section = sections[index]
                sections[index] = AgentCommandCenterSection(
                    id: section.id,
                    title: section.title,
                    detail: section.detail,
                    status: section.status,
                    entries: section.entries + [entry]
                )
            } else {
                sections.append(AgentCommandCenterSection(
                    id: entry.item.id,
                    title: entry.item.title,
                    detail: entry.item.detail,
                    status: entry.item.status,
                    entries: [entry]
                ))
            }
        }
        return sections
    }

    private static func entries(for item: AgentMissionControlItem) -> [AgentCommandCenterEntry] {
        let capabilities = AgentControlCenter.capabilities(for: item)
        var entries: [AgentCommandCenterEntry] = []
        entries.append(entry(item, EntryTemplate(
            category: "Navigate",
            title: "Jump",
            detail: item.detail,
            shortcut: "enter",
            action: .jump,
        )))

        if capabilities.reply.isVisible {
            entries.append(entry(item, EntryTemplate(
                category: "Control",
                title: "Reply",
                detail: replyDetail(for: item),
                shortcut: "r",
                action: .reply
            )))
        }
        if capabilities.stop.isVisible {
            entries.append(entry(item, EntryTemplate(
                category: "Control",
                title: "Stop",
                detail: "Send Escape",
                shortcut: "s",
                action: .stop
            )))
        }
        if capabilities.restart.isVisible {
            entries.append(entry(item, EntryTemplate(
                category: "Session",
                title: "New Run",
                detail: "Start in the same worktree",
                shortcut: "n",
                action: .newRun
            )))
        }
        if capabilities.resume.isVisible {
            entries.append(entry(item, EntryTemplate(
                category: "Session",
                title: "Resume",
                detail: "Continue the saved session",
                shortcut: "e",
                action: .resume
            )))
        }
        if capabilities.verify.isVisible {
            entries.append(entry(item, EntryTemplate(
                category: "Review",
                title: "Verify",
                detail: item.verification.status.title,
                shortcut: "v",
                action: .verify
            )))
        }
        entries.append(contentsOf: changedFileEntries(item, capabilities: capabilities))
        return entries
    }

    private static func replyDetail(for item: AgentMissionControlItem) -> String {
        switch item.status {
        case .running:
            "Queue message in active session"
        case .needsAttention:
            "Answer this run"
        case .completed,
             .failed,
             .notice:
            "Continue this run"
        }
    }

    private static func changedFileEntries(
        _ item: AgentMissionControlItem,
        capabilities: AgentRunCapabilities
    ) -> [AgentCommandCenterEntry] {
        item.changedFiles.flatMap { file in
            var entries: [AgentCommandCenterEntry] = []
            if capabilities.openFiles.isVisible, file.status != .deleted {
                entries.append(entry(item, EntryTemplate(
                    category: "Files",
                    title: "Open File",
                    detail: file.path,
                    shortcut: "f",
                    action: .openFile(file)
                )))
            }
            if capabilities.openDiffs.isVisible {
                entries.append(entry(item, EntryTemplate(
                    category: "Files",
                    title: "Open Diff",
                    detail: file.path,
                    shortcut: "d",
                    action: .openDiff(file)
                )))
            }
            return entries
        }
    }

    private static func entry(_ item: AgentMissionControlItem, _ template: EntryTemplate) -> AgentCommandCenterEntry {
        AgentCommandCenterEntry(
            id: "\(item.id)|\(item.status.rawValue)|\(template.title)|\(template.detail)",
            item: item,
            category: template.category,
            title: template.title,
            detail: template.detail,
            shortcut: template.shortcut,
            action: template.action
        )
    }
}
