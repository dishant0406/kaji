import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TopBarIDEPicker: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var state = TopBarIDEPickerState()
    @State private var showPopover = false
    @State private var hovered = false

    private var projectPath: String? {
        guard let projectID = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == projectID })
        else { return nil }
        guard let key = appState.activeWorktreeKey(for: projectID) else { return project.path }
        return worktreeStore.worktree(projectID: projectID, worktreeID: key.worktreeID)?.path ?? project.path
    }

    var body: some View {
        Group {
            if projectPath != nil {
                button
            }
        }
        .onAppear { state.refreshIfNeeded() }
    }

    private var button: some View {
        Button {
            showPopover.toggle()
            state.refreshIfNeeded()
        } label: {
            HStack(spacing: 7) {
                if state.isOpening {
                    KajiSpinner(size: 11, lineWidth: 1.4)
                } else if let iconPath = state.selectedIDEIconPath {
                    ExternalIDEAppIcon(path: iconPath, size: 14)
                }
                Text(state.selectedIDE?.displayName ?? "IDE")
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(active ? KajiTheme.fg : KajiTheme.fgMuted)
                    .lineLimit(1)
                    .frame(maxWidth: 94, alignment: .leading)
                KajiIcon(systemName: "chevron.down", size: 8)
                    .foregroundStyle(KajiTheme.fgDim)
                    .rotationEffect(.degrees(showPopover ? 180 : 0))
                    .animation(KajiMotion.fast, value: showPopover)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(controlSurface)
            .overlay(border)
            .contentShape(RoundedRectangle(cornerRadius: KajiShape.tileRadius))
        }
        .buttonStyle(.borderless)
        .disabled(state.isOpening)
        .onHover { hovered = $0 }
        .kajiHoverEffect(isActive: active)
        .kajiPointer()
        .help(helpText)
        .accessibilityLabel("Open Project in IDE")
        .kajiPopover(isPresented: $showPopover, preferredEdge: .bottom) {
            TopBarIDEPickerPopover(
                ides: state.ides,
                iconPathsByIDEID: state.iconPathsByIDEID,
                isLoading: state.isLoading,
                selectedID: state.selectedIDEID,
                onSelect: open,
                onChooseApplication: chooseApplication
            )
        }
    }

    private var active: Bool {
        showPopover || hovered || state.isOpening
    }

    private var controlSurface: some View {
        KajiControlSurface(
            base: active ? KajiTheme.surface : .clear,
            cornerRadius: KajiShape.tileRadius,
            isInteractive: true
        )
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: KajiShape.tileRadius)
            .strokeBorder(KajiTheme.border.opacity(active ? 0.85 : 0.35), lineWidth: 1)
    }

    private var helpText: String {
        guard let selected = state.selectedIDE else { return "Choose an IDE" }
        return "Open active worktree in \(selected.displayName)"
    }

    private func open(_ ide: ExternalIDE) {
        guard let projectPath else { return }
        showPopover = false
        state.open(ide, projectPath: projectPath)
    }

    private func chooseApplication() {
        showPopover = false
        let panel = NSOpenPanel()
        panel.title = "Choose IDE"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url, let projectPath else { return }
        state.addCustomApplication(at: url)
        state.openSelected(projectPath: projectPath)
    }
}
