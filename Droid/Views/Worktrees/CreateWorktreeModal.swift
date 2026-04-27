import SwiftUI

struct CreateWorktreeModal: View {
    let project: Project
    let onFinish: (CreateWorktreeResult) -> Void
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var name = ""
    @State private var branchName = ""
    @State private var branchNameEdited = false
    @State private var createNewBranch = true
    @State private var selectedExistingBranch = ""
    @State private var availableBranches: [String] = []
    @State private var setupCommands: [String] = []
    @State private var runSetup = false
    @State private var inProgress = false
    @State private var errorMessage: String?
    private let gitRepository = GitRepositoryService()
    private let gitWorktree = GitWorktreeService.shared
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CreateWorktreeFormSection(
                        "Worktree",
                        detail: "Create a named worktree with a matching folder and branch target."
                    ) {
                        CreateWorktreeLabeledField("Name") {
                            DroidInput(placeholder: "feature-x", text: $name, monospaced: true)
                        }
                    }
                    CreateWorktreeFormSection(
                        "Branch",
                        detail: "Choose whether this worktree starts from a new branch or an existing branch."
                    ) {
                        SegmentedPicker(
                            selection: $createNewBranch,
                            options: [(true, "Create branch"), (false, "Use existing")]
                        )
                        if createNewBranch {
                            CreateWorktreeLabeledField("Branch name") {
                                DroidInput(placeholder: "feature-x", text: $branchName, monospaced: true)
                                    .onChange(of: branchName) { _, newValue in
                                        branchNameEdited = newValue != name
                                    }
                            }
                        } else {
                            CreateWorktreeLabeledField("Existing branch") {
                                DroidSelect(
                                    options: availableBranches.map {
                                        DroidSelectOption(id: $0, title: $0, value: $0)
                                    },
                                    selection: $selectedExistingBranch,
                                    placeholder: availableBranches.isEmpty ? "No branches" : "Select branch"
                                )
                            }
                        }
                    }
                    CreateWorktreeFormSection("Setup", showsDivider: errorMessage == nil) {
                        CreateWorktreeSetupSection(
                            projectPath: project.path,
                            setupCommands: setupCommands,
                            runSetup: $runSetup
                        )
                    }
                    if let errorMessage {
                        VStack(alignment: .leading, spacing: 0) {
                            Rectangle().fill(DroidTheme.border).frame(height: 1)
                            Text(errorMessage)
                                .droidFont(size: 11)
                                .foregroundStyle(DroidTheme.diffRemoveFg)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                        }
                    }
                }
                .background(
                    DroidTheme.bg.opacity(0.34)
                )
            }
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            footer
        }
        .frame(width: 560, height: 500)
        .background(
            TranslucentSurface(
                base: DroidTheme.tertiaryBackground,
                material: .hudWindow,
                tintOpacity: 0.66,
                gradientOpacity: 0.08
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: DroidShape.modalRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DroidShape.modalRadius)
                .stroke(DroidTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
        .task {
            await loadBranches()
            loadSetupCommands()
        }
        .onChange(of: name) { _, newValue in
            guard createNewBranch, !branchNameEdited else { return }
            branchName = newValue
        }
        .onChange(of: createNewBranch) { _, isCreatingNewBranch in
            guard isCreatingNewBranch, !branchNameEdited else { return }
            branchName = name
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Create Worktree")
                    .droidFont(size: 13, weight: .semibold)
                    .foregroundStyle(DroidTheme.fg)
                Text(project.name)
                    .droidFont(size: 12, weight: .medium)
                    .foregroundStyle(DroidTheme.fgMuted)
                    .lineLimit(1)
            }
            Spacer()
            IconButton(symbol: "xmark", accessibilityLabel: "Close Worktree Modal") {
                onFinish(.cancelled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            DroidTheme.chrome.opacity(0.42)
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel") { onFinish(.cancelled) }
                .buttonStyle(DroidButtonStyle(.secondary))
            Button {
                Task { await create() }
            } label: {
                HStack(spacing: 6) {
                    if inProgress {
                        DroidSpinner(size: 11, lineWidth: 1.4, color: DroidTheme.bg)
                    }
                    Text(inProgress ? "Creating..." : "Create")
                }
            }
            .buttonStyle(DroidButtonStyle(.primary))
            .disabled(!canCreate || inProgress)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            DroidTheme.chrome.opacity(0.42)
        )
    }

    private func loadSetupCommands() {
        setupCommands = WorktreeConfig.load(fromProjectPath: project.path)?.setup.map(\.command).filter { !$0.isEmpty } ?? []
    }

    private var canCreate: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return createNewBranch ? !branchName.trimmingCharacters(in: .whitespaces).isEmpty : !selectedExistingBranch.isEmpty
    }

    private func loadBranches() async {
        do {
            let branches = try await gitRepository.listBranches(repoPath: project.path)
            await MainActor.run {
                availableBranches = branches
                if selectedExistingBranch.isEmpty {
                    selectedExistingBranch = branches.first ?? ""
                }
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func create() async {
        inProgress = true
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let branch = createNewBranch ? branchName.trimmingCharacters(in: .whitespaces) : selectedExistingBranch
        let path = DroidFileStorage.worktreeDirectory(forProjectID: project.id, name: Self.slug(from: trimmedName))
            .path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: path) else {
            inProgress = false
            errorMessage = "A worktree with this name already exists on disk."
            return
        }
        do {
            try await gitWorktree.addWorktree(repoPath: project.path, path: path, branch: branch, createBranch: createNewBranch)
            let worktree = Worktree(name: trimmedName, path: path, branch: branch, ownsBranch: createNewBranch, isPrimary: false)
            worktreeStore.add(worktree, to: project.id)
            inProgress = false
            onFinish(.created(worktree, runSetup: runSetup))
        } catch {
            inProgress = false
            errorMessage = error.localizedDescription
        }
    }

    private static func slug(from name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let collapsed = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }
}
