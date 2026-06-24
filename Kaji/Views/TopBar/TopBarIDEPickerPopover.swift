import SwiftUI

struct TopBarIDEPickerPopover: View {
    let ides: [ExternalIDE]
    let iconPathsByIDEID: [String: String]
    let isLoading: Bool
    let selectedID: String?
    let onSelect: (ExternalIDE) -> Void
    let onChooseApplication: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if isLoading, ides.isEmpty {
                loadingState
            } else if ides.isEmpty {
                emptyState
            } else {
                ForEach(ides) { ide in
                    TopBarIDERow(
                        ide: ide,
                        iconPath: iconPathsByIDEID[ide.id],
                        isSelected: ide.id == selectedID,
                        action: { onSelect(ide) }
                    )
                }
            }
            Divider().overlay(KajiTheme.border.opacity(0.55))
            footerButton
        }
        .frame(width: 280)
        .background(
            TranslucentSurface(
                base: KajiTheme.tertiaryBackground,
                material: .menu,
                tintOpacity: 0.74
            )
        )
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Open Project")
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text("Select an IDE for the active worktree")
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No supported IDEs found")
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(KajiTheme.fg)
            Text("Choose an application to add it here.")
                .kajiFont(size: 10)
                .foregroundStyle(KajiTheme.fgMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            KajiSpinner(size: 16, lineWidth: 1.6)
            Text("Looking for installed IDEs")
                .kajiFont(size: 12, weight: .medium)
                .foregroundStyle(KajiTheme.fg)
            Text("This will not block Kaji.")
                .kajiFont(size: 10)
                .foregroundStyle(KajiTheme.fgMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var footerButton: some View {
        Button(action: onChooseApplication) {
            HStack {
                Text("Choose Application…")
                    .kajiFont(size: 12, weight: .medium)
                Spacer(minLength: 0)
            }
            .foregroundStyle(KajiTheme.fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
