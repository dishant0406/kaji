import SwiftUI

struct InlineEditOverlay: View {
    @Bindable var state: EditorTabState
    let project: Project?
    let worktree: Worktree?

    @State private var instruction = ""
    @State private var proposal = ""
    @State private var provider: AskProvider = .opencode
    @State private var selectedModel = ""
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var generatedBy: String?
    @State private var copiedAskPrompt = false
    @State private var editService: any AgentEditProviding = AgentEditService()
    @State private var generationTask: Task<Void, Never>?
    @State private var settings = InlineEditSettings.shared

    var body: some View {
        KajiModalOverlay(onDismiss: dismiss) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().overlay(KajiTheme.border)
                InlineEditPromptSection(
                    instruction: $instruction,
                    provider: $provider,
                    selectedModel: $selectedModel,
                    providers: availableProviders,
                    models: modelOptions,
                    isGenerating: isGenerating,
                    generationLabel: generationLabel,
                    generationError: generationError,
                    statusText: statusText,
                    onSubmit: generateProposal
                )
                Divider().overlay(KajiTheme.border)
                diffPreview
                Divider().overlay(KajiTheme.border)
                InlineEditProposalEditor(proposal: $proposal)
                Divider().overlay(KajiTheme.border)
                InlineEditFooter(
                    copiedAskPrompt: copiedAskPrompt,
                    isGenerating: isGenerating,
                    canGenerate: !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    canApply: !proposal.isEmpty && !isGenerating,
                    onReject: dismiss,
                    onCopyAskPrompt: copyAskPrompt,
                    onOpenInAsk: openInAsk,
                    onGenerate: generateProposal,
                    onStop: cancelGeneration,
                    onApply: { state.applyInlineEdit(proposal: proposal) }
                )
            }
            .frame(width: 760, height: 640)
            .background(KajiTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: KajiShape.modalRadius))
            .overlay(RoundedRectangle(cornerRadius: KajiShape.modalRadius).stroke(KajiTheme.borderStrong, lineWidth: 1))
            .onAppear(perform: prepare)
            .onDisappear(perform: cancelGeneration)
            .onChange(of: provider) { _, newProvider in
                settings.providerID = newProvider.rawValue
                selectedModel = defaultModel(for: newProvider) ?? ""
            }
            .onChange(of: selectedModel) { _, newModel in
                settings.setModelID(newModel.isEmpty ? nil : newModel, for: provider.rawValue)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            KajiIcon(systemName: "wand.and.sparkles", size: 13)
                .foregroundStyle(KajiTheme.accent)
            Text("Inline Edit")
                .kajiFont(size: 14, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer()
            Button(action: dismiss) {
                KajiIcon(systemName: "xmark", size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var diffPreview: some View {
        InlineEditDiffPreview(original: state.inlineEditOriginal, proposal: proposal)
            .padding(14)
    }

    private func prepare() {
        instruction = state.inlineEditInstruction
        proposal = state.inlineEditProposal.isEmpty ? state.inlineEditOriginal : state.inlineEditProposal
        provider = defaultProvider
        selectedModel = defaultModel(for: provider) ?? ""
    }

    private func dismiss() {
        cancelGeneration()
        state.inlineEditVisible = false
    }

    private func copyAskPrompt() {
        let prompt = askPrompt()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copiedAskPrompt = true
        ToastState.shared.show("Inline edit prompt copied")
    }

    private func openInAsk() {
        AskPrefillState.shared.set(askPrompt())
        state.inlineEditVisible = false
        NotificationCenter.default.post(name: .openAskWithPrefill, object: nil)
    }

    private func generateProposal() {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else { return }
        guard let projectPath = worktree?.path ?? project?.path else {
            generationError = "No active project is available."
            return
        }
        cancelGeneration()
        isGenerating = true
        generationError = nil
        generatedBy = nil
        let request = AgentEditRequest(
            filePath: state.filePath,
            projectPath: projectPath,
            selectedText: state.inlineEditOriginal,
            instruction: trimmedInstruction,
            provider: provider,
            languageID: MonacoLanguageMapper.languageID(for: state.filePath),
            model: selectedModel.isEmpty ? nil : selectedModel
        )
        generationTask = Task {
            do {
                let response = try await editService.generateEdit(request: request)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    proposal = response.replacement
                    state.inlineEditInstruction = trimmedInstruction
                    state.inlineEditProposal = response.replacement
                    generatedBy = generationLabel
                    isGenerating = false
                    ToastState.shared.show("Inline edit generated with \(generationLabel)")
                }
            } catch {
                await MainActor.run {
                    if error is CancellationError {
                        generationError = nil
                    } else {
                        generationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                    isGenerating = false
                }
            }
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    private func askPrompt() -> String {
        InlineEditPromptBuilder.prompt(
            filePath: state.filePath,
            instruction: instruction.isEmpty ? "Improve this code" : instruction,
            selectedCode: state.inlineEditOriginal,
            languageID: MonacoLanguageMapper.languageID(for: state.filePath)
        )
    }

    private var availableProviders: [AskProvider] {
        AskProvider.allCases.filter { provider in
            provider != .terminal && provider.definition != nil
        }
    }

    private var defaultProvider: AskProvider {
        if let saved = availableProviders.first(where: { $0.rawValue == settings.providerID }) { return saved }
        if availableProviders.contains(.opencode) { return .opencode }
        return availableProviders.first ?? .opencode
    }

    private var modelOptions: [String] {
        ParentAgentCodingProviderCatalog.modelOptions(for: provider, projectPath: worktree?.path ?? project?.path)
    }

    private func defaultModel(for provider: AskProvider) -> String? {
        let options = ParentAgentCodingProviderCatalog.modelOptions(for: provider, projectPath: worktree?.path ?? project?.path)
        if let saved = settings.modelID(for: provider.rawValue), options.contains(saved) { return saved }
        return CodingAgentRegistry.shared.agent(id: provider.rawValue)?.defaultModel(projectPath: worktree?.path ?? project?.path)
    }

    private var generationLabel: String {
        selectedModel.isEmpty ? provider.title : "\(provider.title) / \(selectedModel)"
    }

    private var statusText: String {
        if let generatedBy { return "Generated with \(generatedBy). You can edit before applying." }
        return "Generate a proposal directly, or open the same prompt in Ask."
    }
}
