import SwiftUI

struct CreatePRModal: View {
    struct Context {
        let currentBranch: String
        let defaultBranch: String?
        let availableBaseBranches: [String]
        let isLoadingBranches: Bool
        let hasStagedChanges: Bool
        let hasUnstagedChanges: Bool
    }

    let context: Context
    let inProgress: Bool
    let errorMessage: String?
    let onSubmit: (
        _ baseBranch: String,
        _ title: String,
        _ body: String,
        _ branchStrategy: VCSTabState.PRBranchStrategy,
        _ includeMode: VCSTabState.PRIncludeMode,
        _ draft: Bool
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
    @State private var didApplyDefaults = false
    @State private var currentBranchSnapshot: String?

    private var resolvedCurrentBranch: String { currentBranchSnapshot ?? context.currentBranch }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBranchName: String { newBranchName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var needsNewBranch: Bool { !baseBranch.isEmpty && baseBranch == resolvedCurrentBranch }
    private var hasAnyChanges: Bool { context.hasStagedChanges || context.hasUnstagedChanges }
    private var createEnabled: Bool {
        !trimmedTitle.isEmpty && !baseBranch.isEmpty && (!needsNewBranch || !trimmedBranchName.isEmpty) && !inProgress
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    branchSection
                    detailsSection
                    optionsSection
                    if let errorMessage {
                        Rectangle().fill(DroidTheme.border).frame(height: 1)
                        Text(errorMessage)
                            .droidFont(size: 11)
                            .foregroundStyle(DroidTheme.diffRemoveFg)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                    }
                }
                .background(DroidTheme.bg.opacity(0.34))
            }
            Rectangle().fill(DroidTheme.border).frame(height: 1)
            footer
        }
        .frame(width: 620, height: 560)
        .background(TranslucentSurface(base: DroidTheme.tertiaryBackground, material: .hudWindow, tintOpacity: 0.66, gradientOpacity: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: DroidShape.modalRadius))
        .overlay(RoundedRectangle(cornerRadius: DroidShape.modalRadius).stroke(DroidTheme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
        .onAppear(perform: applyDefaults)
        .onChange(of: context.availableBaseBranches) { _, _ in applyDefaults() }
        .onChange(of: title) { _, newValue in
            guard !userEditedBranchName else { return }
            programmaticBranchNameChange = true
            newBranchName = Self.slugify(newValue)
        }
    }

    private var header: some View {
        HStack {
            Text("Create Pull Request")
                .droidFont(size: 13, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Spacer()
            IconButton(symbol: "xmark", accessibilityLabel: "Close Pull Request Modal", action: onCancel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DroidTheme.chrome.opacity(0.42))
    }

    private var branchSection: some View {
        CreateWorktreeFormSection(
            "Target",
            detail: "Choose the base branch and decide whether this PR should stay on the current branch."
        ) {
            CreateWorktreeLabeledField("Base branch") {
                if context.isLoadingBranches, context.availableBaseBranches.isEmpty {
                    HStack(spacing: 8) {
                        DroidSpinner(size: 12, lineWidth: 1.4, color: DroidTheme.fgMuted)
                        Text("Loading remote branches")
                            .droidFont(size: 11)
                            .foregroundStyle(DroidTheme.fgDim)
                    }
                } else {
                    DroidSelect(
                        options: branchOptions,
                        selection: $baseBranch,
                        placeholder: context.availableBaseBranches.isEmpty ? "No branches" : "Select branch"
                    )
                }
            }
            if needsNewBranch {
                CreateWorktreeLabeledField("New branch") {
                    DroidInput(placeholder: "feature-x", text: $newBranchName, monospaced: true)
                        .onChange(of: newBranchName) { _, _ in
                            guard !programmaticBranchNameChange else {
                                programmaticBranchNameChange = false
                                return
                            }
                            userEditedBranchName = true
                        }
                }
            }
        }
    }

    private var detailsSection: some View {
        CreateWorktreeFormSection("Details", detail: "Write a clear title and optional context for reviewers.") {
            CreateWorktreeLabeledField("Title") {
                DroidInput(placeholder: "Short summary of the change", text: $title)
            }
            CreateWorktreeLabeledField("Description") {
                DroidTextArea(
                    placeholder: "What changed and what should reviewers focus on?",
                    text: $bodyText,
                    minHeight: 124,
                    maxHeight: 160
                )
            }
        }
    }

    private var optionsSection: some View {
        CreateWorktreeFormSection("Options", showsDivider: false) {
            if hasAnyChanges, context.hasStagedChanges, context.hasUnstagedChanges {
                CreateWorktreeLabeledField("Include") {
                    SegmentedPicker(selection: $includeAll, options: [(true, "All changes"), (false, "Staged only")])
                }
            }
            SettingsDetailToggleRow(
                label: "Create as draft",
                detail: "Open the pull request in draft mode until it is ready for review.",
                isOn: $draft
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(DroidButtonStyle(.secondary))
                .disabled(inProgress)
            Button(action: submit) {
                HStack(spacing: 6) {
                    if inProgress {
                        DroidSpinner(size: 11, lineWidth: 1.4, color: DroidTheme.bg)
                    }
                    Text(inProgress ? "Creating..." : "Create PR")
                }
            }
            .buttonStyle(DroidButtonStyle(.primary))
            .opacity(createEnabled ? 1 : 0.42)
            .disabled(!createEnabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DroidTheme.chrome.opacity(0.42))
    }

    private var branchOptions: [DroidSelectOption<String>] {
        context.availableBaseBranches.map { DroidSelectOption(id: $0, title: $0, value: $0) }
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
    }

    private func submit() {
        let branchStrategy: VCSTabState.PRBranchStrategy = needsNewBranch ? .createNew(name: trimmedBranchName) : .useCurrent
        let includeMode: VCSTabState.PRIncludeMode = !hasAnyChanges ? .none : (includeAll ? .all : .stagedOnly)
        onSubmit(baseBranch, trimmedTitle, bodyText, branchStrategy, includeMode, draft)
    }

    private static func slugify(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = title.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(String(scalars).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-").prefix(20))
    }
}
