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
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CreateWorktreeFormSection(
                        "Workspace",
                        detail: "Create a Rift workspace with a matching folder and branch target."
                    ) {
                        CreateWorktreeLabeledField("Name") {
                            KajiInput(placeholder: "feature-x", text: $name, monospaced: true)
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
                                KajiInput(placeholder: "feature-x", text: $branchName, monospaced: true)
                                    .onChange(of: branchName) { _, newValue in
                                        branchNameEdited = newValue != name
                                    }
                            }
                        } else {
                            CreateWorktreeLabeledField("Existing branch") {
                                KajiSelect(
                                    options: availableBranches.map {
                                        KajiSelectOption(id: $0, title: $0, value: $0)
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
                        CreateWorktreeErrorSection(message: errorMessage)
                    }
                }
                .background(
                    KajiTheme.bg.opacity(0.34)
                )
            }
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            footer
        }
        .frame(width: 560, height: 500)
        .background(
            TranslucentSurface(
                base: KajiTheme.tertiaryBackground,
                material: .hudWindow,
                tintOpacity: 0.66,
                gradientOpacity: 0.08
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: KajiShape.modalRadius))
        .overlay(
            RoundedRectangle(cornerRadius: KajiShape.modalRadius)
                .stroke(KajiTheme.border, lineWidth: 1)
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
                Text("Create Workspace")
                    .kajiFont(size: 13, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Text(project.name)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(KajiTheme.fgMuted)
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
            KajiTheme.chrome.opacity(0.42)
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel") { onFinish(.cancelled) }
                .buttonStyle(KajiButtonStyle(.secondary))
            Button {
                Task { await create() }
            } label: {
                HStack(spacing: 6) {
                    if inProgress {
                        KajiSpinner(size: 11, lineWidth: 1.4, color: KajiTheme.bg)
                    }
                    Text(inProgress ? "Creating..." : "Create")
                }
            }
            .buttonStyle(KajiButtonStyle(.primary))
            .disabled(!canCreate || inProgress)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            KajiTheme.chrome.opacity(0.42)
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
        do {
            let worktree = try await RiftWorkspaceCreator.create(RiftWorkspaceCreationRequest(
                project: project,
                name: trimmedName,
                branch: branch,
                createBranch: createNewBranch
            ))
            worktreeStore.add(worktree, to: project.id)
            inProgress = false
            onFinish(.created(worktree, runSetup: runSetup))
        } catch {
            inProgress = false
            errorMessage = error.localizedDescription
        }
    }
}
