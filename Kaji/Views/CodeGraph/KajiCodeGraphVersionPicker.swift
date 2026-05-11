import SwiftUI

struct KajiCodeGraphVersionPicker: View {
    let versions: [KajiCodeGraphVersionEntry]
    let activeVersionID: String?
    let onLatest: () -> Void
    let onSelect: (KajiCodeGraphVersionEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Versions")
                .kajiFont(size: 10, weight: .semibold)
                .foregroundStyle(KajiTheme.fgDim)
            HStack(spacing: 6) {
                Button("Latest") { onLatest() }
                    .buttonStyle(KajiButtonStyle(activeVersionID == nil ? .primary : .secondary, size: .small))
                Menu {
                    ForEach(versions, id: \.id) { version in
                        Button(versionTooltip(version)) {
                            onSelect(version)
                        }
                    }
                } label: {
                    Text(activeVersionTitle)
                        .kajiFont(size: 11, weight: .medium)
                        .foregroundStyle(KajiTheme.fg)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 130, alignment: .leading)
                }
                .menuStyle(.button)
                .buttonStyle(KajiButtonStyle(activeVersionID == nil ? .secondary : .primary, size: .small))
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

    private func versionLabel(_ version: KajiCodeGraphVersionEntry) -> String {
        version.git.shortCommit ?? version.id
    }

    private func versionTooltip(_ version: KajiCodeGraphVersionEntry) -> String {
        let branch = version.git.branch ?? "git"
        let dirty = version.git.isDirty ? " dirty" : ""
        return "\(branch) @ \(versionLabel(version))\(dirty)"
    }
}
