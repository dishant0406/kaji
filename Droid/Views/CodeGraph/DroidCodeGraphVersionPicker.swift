import SwiftUI

struct DroidCodeGraphVersionPicker: View {
    let versions: [DroidCodeGraphVersionEntry]
    let activeVersionID: String?
    let onLatest: () -> Void
    let onSelect: (DroidCodeGraphVersionEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Versions")
                .droidFont(size: 10, weight: .semibold)
                .foregroundStyle(DroidTheme.fgDim)
            HStack(spacing: 6) {
                Button("Latest") { onLatest() }
                    .buttonStyle(DroidButtonStyle(activeVersionID == nil ? .primary : .secondary, size: .small))
                Menu {
                    ForEach(versions, id: \.id) { version in
                        Button(versionTooltip(version)) {
                            onSelect(version)
                        }
                    }
                } label: {
                    Text(activeVersionTitle)
                        .droidFont(size: 11, weight: .medium)
                        .foregroundStyle(DroidTheme.fg)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 130, alignment: .leading)
                }
                .menuStyle(.button)
                .buttonStyle(DroidButtonStyle(activeVersionID == nil ? .secondary : .primary, size: .small))
                .help("Open an archived graph version")
            }
        }
    }

    private var activeVersionTitle: String {
        guard let activeVersionID, let version = versions.first(where: { $0.id == activeVersionID }) else {
            return "History"
        }
        return versionLabel(version)
    }

    private func versionLabel(_ version: DroidCodeGraphVersionEntry) -> String {
        version.git.shortCommit ?? version.id
    }

    private func versionTooltip(_ version: DroidCodeGraphVersionEntry) -> String {
        let branch = version.git.branch ?? "git"
        let dirty = version.git.isDirty ? " dirty" : ""
        return "\(branch) @ \(versionLabel(version))\(dirty)"
    }
}
