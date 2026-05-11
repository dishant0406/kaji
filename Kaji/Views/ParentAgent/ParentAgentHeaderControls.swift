import AppKit
import SwiftUI

struct ParentAgentHeaderControls: View {
    let task: ParentAgentTask?
    let onNewThread: () -> Void
    let showsNewThread: Bool

    var body: some View {
        HStack(spacing: 8) {
            KajiPill(title: providerLabel, leadingIcon: "sparkles", trailingIcon: "chevron.down", variant: .filled) {
                NotificationCenter.default.post(name: .openParentAgentSettings, object: nil)
            }
            .help("Parent Agent settings")

            if showsNewThread {
                KajiPill(title: "New thread", leadingIcon: "plus", variant: .plain, action: onNewThread)
                    .help("Start a new parent-agent thread")
                KajiPill(title: "Copy thread", leadingIcon: "doc.on.doc", variant: .plain) {
                    copyThread()
                }
                .help("Copy full parent-agent thread")
            }
        }
    }

    private var providerLabel: String {
        let settings = ParentAgentSettingsStore.shared
        return "\(settings.provider.title) / \(settings.modelID)"
    }

    private func copyThread() {
        guard let task else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(threadText(task), forType: .string)
    }

    private func threadText(_ task: ParentAgentTask) -> String {
        var lines = ["Parent Agent Thread", "Task ID: \(task.id.uuidString)", "Status: \(task.status.rawValue)", ""]
        for item in task.timeline {
            lines.append("[\(item.kind.rawValue)] \(item.title)")
            if !item.detail.isEmpty { lines.append(item.detail) }
            if let childRunID = item.childRunID { lines.append("childRunID: \(childRunID.uuidString)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
