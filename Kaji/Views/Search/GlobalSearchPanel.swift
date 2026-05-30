import SwiftUI

struct GlobalSearchPanel: View {
    let projectPath: String
    let onOpenMatch: (ProjectTextSearchMatch) -> Void
    let onReplaceComplete: ([String]) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var replacement = ""
    @State private var groups: [ProjectTextSearchFileGroup] = []
    @State private var isSearching = false
    @State private var isReplacing = false
    @State private var replaceVisible = false
    @State private var replaceMessage: String?
    @State private var replacePreview: ProjectTextReplacePreview?
    @State private var searchTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            searchField
            if replaceVisible {
                replaceField
                    .transition(KajiMotion.disclosureTransition(reduceMotion: reduceMotion))
                Rectangle().fill(KajiTheme.border).frame(height: 1)
                    .transition(.opacity)
            }
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            resultsList
        }
        .background(KajiTheme.bg)
        .overlay { replaceConfirmationOverlay }
        .onAppear { searchFocused = true }
        .onDisappear { searchTask?.cancel() }
        .animation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion), value: replaceVisible)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Search")
                .kajiFont(size: 12, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer()
            Button(action: onClose) {
                KajiIcon(systemName: "xmark", size: 10)
                    .foregroundStyle(KajiTheme.fgMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Search")
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(KajiMotion.preferred(KajiMotion.panel, reduceMotion: reduceMotion)) {
                        replaceVisible.toggle()
                    }
                } label: {
                    KajiIcon(systemName: replaceVisible ? "chevron.down" : "chevron.right", size: 10)
                        .foregroundStyle(KajiTheme.fgMuted)
                }
                .buttonStyle(.plain)
                KajiIcon(systemName: "magnifyingglass", size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                TextField("Search in files", text: $query)
                    .textFieldStyle(.plain)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fg)
                    .focused($searchFocused)
                    .onSubmit { performSearch() }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(KajiTheme.border, lineWidth: 1))

            Text(statusText)
                .kajiFont(size: 10)
                .foregroundStyle(KajiTheme.fgDim)
        }
        .padding(12)
        .onChange(of: query) { _, _ in scheduleSearch() }
    }

    private var replaceField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                KajiIcon(systemName: "arrow.2.squarepath", size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                TextField("Replace", text: $replacement)
                    .textFieldStyle(.plain)
                    .kajiFont(size: 12)
                    .foregroundStyle(KajiTheme.fg)
                Button("Replace All") {
                    prepareReplacePreview()
                }
                .buttonStyle(GlobalSearchTextButtonStyle())
                .disabled(groups.isEmpty || isSearching || isReplacing)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(KajiTheme.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(KajiTheme.border, lineWidth: 1))
            if let replaceMessage {
                Text(replaceMessage)
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var resultsList: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState("Type to search across the project")
            } else if isSearching, groups.isEmpty {
                emptyState("Searching...")
            } else if groups.isEmpty {
                emptyState("No results")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(groups) { group in
                            GlobalSearchFileGroupView(group: group, onOpenMatch: onOpenMatch)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: String {
        if isReplacing { return "Replacing..." }
        if isSearching { return "Searching..." }
        let count = groups.reduce(0) { $0 + $1.matches.count }
        if count.signum() == 0 { return "Search results appear grouped by file" }
        return "\(count) result\(count == 1 ? "" : "s") in \(groups.count) file\(groups.count == 1 ? "" : "s")"
    }

    private func emptyState(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .kajiFont(size: 12)
                .foregroundStyle(KajiTheme.fgDim)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        replaceMessage = nil
        replacePreview = nil
        let currentQuery = query
        guard !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            groups = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let results = await ProjectTextSearchService.search(query: currentQuery, in: projectPath)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                groups = results
                isSearching = false
            }
        }
    }

    private func performSearch() {
        searchTask?.cancel()
        replaceMessage = nil
        replacePreview = nil
        isSearching = true
        let currentQuery = query
        searchTask = Task {
            let results = await ProjectTextSearchService.search(query: currentQuery, in: projectPath)
            await MainActor.run {
                groups = results
                isSearching = false
            }
        }
    }

    private var replaceConfirmationOverlay: some View {
        Group {
            if let replacePreview {
                ZStack {
                    Color.black.opacity(0.16)
                        .ignoresSafeArea()
                        .onTapGesture { self.replacePreview = nil }
                    GlobalSearchReplaceConfirmation(
                        preview: replacePreview,
                        onCancel: { self.replacePreview = nil },
                        onConfirm: {
                            self.replacePreview = nil
                            replaceAll()
                        }
                    )
                    .padding(20)
                }
            }
        }
    }

    private func prepareReplacePreview() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !groups.isEmpty else { return }
        replacePreview = ProjectTextReplacePreview.make(groups: groups, replacement: replacement)
    }

    private func replaceAll() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !groups.isEmpty else { return }
        searchTask?.cancel()
        isReplacing = true
        replaceMessage = nil
        let currentGroups = groups
        let currentReplacement = replacement
        Task {
            do {
                let changedPaths = try await ProjectTextSearchService.replace(
                    query: trimmed,
                    groups: currentGroups,
                    with: currentReplacement
                )
                let refreshed = await ProjectTextSearchService.search(query: trimmed, in: projectPath)
                await MainActor.run {
                    groups = refreshed
                    isReplacing = false
                    replaceMessage = "Updated \(changedPaths.count) file\(changedPaths.count == 1 ? "" : "s")"
                    onReplaceComplete(changedPaths)
                }
            } catch {
                await MainActor.run {
                    isReplacing = false
                    replaceMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct GlobalSearchTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .kajiFont(size: 11, weight: .medium)
            .foregroundStyle(isEnabled ? KajiTheme.fg : KajiTheme.fgDim)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(configuration.isPressed ? KajiTheme.surface : KajiTheme.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(KajiTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct GlobalSearchFileGroupView: View {
    let group: ProjectTextSearchFileGroup
    let onOpenMatch: (ProjectTextSearchMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                KajiIcon(systemName: fileIcon, size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                    .frame(width: 14)
                Text(group.relativePath)
                    .kajiFont(size: 11, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(group.matches.count)")
                    .kajiFont(size: 10, design: .monospaced)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)

            ForEach(group.matches) { match in
                GlobalSearchMatchRow(match: match, onOpen: { onOpenMatch(match) })
            }
        }
        .padding(6)
        .background(KajiTheme.chrome.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private var fileIcon: String {
        let ext = URL(fileURLWithPath: group.filePath).pathExtension.lowercased()
        return switch ext {
        case "swift": "swift"
        case "js",
             "jsx",
             "mjs": "j.square"
        case "ts",
             "tsx",
             "mts": "t.square"
        case "py": "p.square"
        case "md",
             "markdown": "doc.richtext"
        default: "doc.text"
        }
    }
}

private struct GlobalSearchMatchRow: View {
    let match: ProjectTextSearchMatch
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(match.line):\(match.column)")
                .kajiFont(size: 10, design: .monospaced)
                .foregroundStyle(KajiTheme.fgDim)
                .frame(width: 48, alignment: .trailing)
            Text(match.preview.isEmpty ? " " : match.preview)
                .kajiFont(size: 11, design: .monospaced)
                .foregroundStyle(KajiTheme.fgMuted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(hovered ? KajiTheme.secondaryBackground : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onOpen)
    }
}
