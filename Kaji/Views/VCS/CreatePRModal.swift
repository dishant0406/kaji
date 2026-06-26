import SwiftUI

struct CreatePRModal: View {
    let context: CreatePRModalContext
    let inProgress: Bool
    let errorMessage: String?
    let onSubmit: (
        _ baseBranch: String,
        _ title: String,
        _ body: String,
        _ branchStrategy: VCSTabState.PRBranchStrategy,
        _ includeMode: VCSTabState.PRIncludeMode,
        _ draft: Bool,
        _ githubAccount: GitHubAccount?
    ) -> Void
    let onCancel: () -> Void

    @State private var baseBranch = ""
    @State private var title = ""
    @State private var bodyText = ""
    @State private var newBranchName = ""
    @State private var userEditedBranchName = false
    @State private var programmaticBranchNameChange = false
    @State private var includeAll = true
    @State private var draft = false
    @State private var selectedGitHubAccountID = ""
    @State private var didApplyDefaults = false
    @State private var currentBranchSnapshot: String?

    private var resolvedCurrentBranch: String { currentBranchSnapshot ?? context.currentBranch }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBranchName: String { newBranchName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var needsNewBranch: Bool { !baseBranch.isEmpty && baseBranch == resolvedCurrentBranch }
    private var hasAnyChanges: Bool { context.hasStagedChanges || context.hasUnstagedChanges }
    private var createEnabled: Bool {
        !trimmedTitle.isEmpty &&
            !baseBranch.isEmpty &&
            (!needsNewBranch || !trimmedBranchName.isEmpty) &&
            !context.isLoadingGitHubAccounts &&
            (!needsGitHubAccountSelection || selectedGitHubAccount != nil) &&
            !inProgress
    }

    var body: some View {
        VStack(spacing: 0) {
            CreatePRModalHeader(onCancel: onCancel)
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    branchSection
                    detailsSection
                    optionsSection
                    if let errorMessage {
                        Rectangle().fill(KajiTheme.border).frame(height: 1)
                        Text(errorMessage)
                            .kajiFont(size: 11)
                            .foregroundStyle(KajiTheme.diffRemoveFg)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                    }
                }
                .background(KajiTheme.bg.opacity(0.34))
            }
            Rectangle().fill(KajiTheme.border).frame(height: 1)
            CreatePRModalFooter(
                inProgress: inProgress,
                createEnabled: createEnabled,
                onCancel: onCancel,
                onSubmit: submit
            )
        }
        .onAppear(perform: applyDefaults)
        .onChange(of: context.availableBaseBranches) { _, _ in applyDefaults() }
        .onChange(of: context.githubAccounts) { _, _ in applyDefaults() }
        .onChange(of: title) { _, newValue in
            guard !userEditedBranchName else { return }
            programmaticBranchNameChange = true
            newBranchName = PullRequestBranchNameSlug.make(from: newValue)
        }
    }

    private var branchSection: some View {
        KajiFormSection(
            "Target",
            detail: "Choose the base branch and decide whether this PR should stay on the current branch."
        ) {
            KajiLabeledField("Base branch") {
                if context.isLoadingBranches, context.availableBaseBranches.isEmpty {
                    HStack(spacing: 8) {
                        KajiSpinner(size: 12, lineWidth: 1.4, color: KajiTheme.fgMuted)
                        Text("Loading remote branches")
                            .kajiFont(size: 11)
                            .foregroundStyle(KajiTheme.fgDim)
                    }
                } else {
                    KajiSelect(
                        options: branchOptions,
                        selection: $baseBranch,
                        placeholder: context.availableBaseBranches.isEmpty ? "No branches" : "Select branch"
                    )
                }
            }
            if needsNewBranch {
                KajiLabeledField("New branch") {
                    KajiInput(placeholder: "feature-x", text: $newBranchName, monospaced: true)
                        .onChange(of: newBranchName) { _, _ in
                            guard !programmaticBranchNameChange else {
                                programmaticBranchNameChange = false
                                return
                            }
                            userEditedBranchName = true
                        }
                }
            }
            CreatePRGitHubAccountField(
                isLoading: context.isLoadingGitHubAccounts,
                accounts: context.githubAccounts,
                selection: $selectedGitHubAccountID
            )
        }
    }

    private var detailsSection: some View {
        KajiFormSection("Details", detail: "Write a clear title and optional context for reviewers.") {
            KajiLabeledField("Title") {
                KajiInput(placeholder: "Short summary of the change", text: $title)
            }
            KajiLabeledField("Description") {
                KajiTextArea(
                    placeholder: "What changed and what should reviewers focus on?",
                    text: $bodyText,
                    minHeight: 124,
                    maxHeight: 160
                )
            }
        }
    }

    private var optionsSection: some View {
        KajiFormSection("Options", showsDivider: false) {
            if hasAnyChanges, context.hasStagedChanges, context.hasUnstagedChanges {
                KajiLabeledField("Include") {
                    SegmentedPicker(selection: $includeAll, options: [(true, "All changes"), (false, "Staged only")])
                }
            }
            KajiDetailToggleRow(
                label: "Create as draft",
                detail: "Open the pull request in draft mode until it is ready for review.",
                isOn: $draft
            )
        }
    }

    private var branchOptions: [KajiSelectOption<String>] {
        context.availableBaseBranches.map { KajiSelectOption(id: $0, title: $0, value: $0) }
    }

    private var needsGitHubAccountSelection: Bool {
        context.githubAccounts.count > 1
    }

    private var selectedGitHubAccount: GitHubAccount? {
        if context.githubAccounts.count == 1 { return context.githubAccounts.first }
        return context.githubAccounts.first { $0.id == selectedGitHubAccountID }
    }

    private func applyDefaults() {
        if currentBranchSnapshot == nil { currentBranchSnapshot = context.currentBranch }
        if baseBranch.isEmpty {
            baseBranch = context.defaultBranch ?? context.availableBaseBranches.first(where: { $0 != resolvedCurrentBranch }) ?? context
                .availableBaseBranches.first ?? ""
        }
        if !didApplyDefaults {
            includeAll = true
            didApplyDefaults = true
        }
        if selectedGitHubAccountID.isEmpty {
            selectedGitHubAccountID = context.githubAccounts.first(where: \.isActive)?.id ?? context.githubAccounts.first?.id ?? ""
        }
    }

    private func submit() {
        let branchStrategy: VCSTabState.PRBranchStrategy = needsNewBranch ? .createNew(name: trimmedBranchName) : .useCurrent
        let includeMode: VCSTabState.PRIncludeMode = !hasAnyChanges ? .none : (includeAll ? .all : .stagedOnly)
        onSubmit(baseBranch, trimmedTitle, bodyText, branchStrategy, includeMode, draft, selectedGitHubAccount)
    }
}
