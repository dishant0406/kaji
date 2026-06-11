import SwiftUI

struct KajiAgentCustomProvidersSection: View {
    let store: KajiAgentStore
    @State private var draft = KajiAgentCustomProvider()
    @State private var editingID: String?
    @State private var isCreating = false
    @State private var isAutoMatching = false
    @State private var matchedAccountText = ""
    @State private var pendingDelete: KajiAgentCustomProvider?

    var body: some View {
        SettingsSection(
            "Custom Providers",
            footer: "Creates providers in \(store.customProvidersState.path). Prefer environment variable names for API keys."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if isEditing {
                    KajiAgentCustomProviderEditor(
                        draft: $draft,
                        locksProviderID: editingID != nil,
                        isAutoMatching: isAutoMatching,
                        matchedAccountText: matchedAccountText,
                        onAutoMatch: autoMatchModels,
                        onSave: save,
                        onCancel: cancel
                    )
                }
                if store.customProvidersState.providers.isEmpty {
                    emptyState
                } else {
                    ForEach(store.customProvidersState.providers) { provider in
                        KajiAgentCustomProviderRow(
                            provider: provider,
                            onEdit: { edit(provider) },
                            onDelete: { pendingDelete = provider }
                        )
                    }
                }
                if !store.customProviderStatus.isEmpty {
                    Text(store.customProviderStatus)
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(store.customProviderStatus.contains("Unable") ? KajiTheme.diffRemoveFg : KajiTheme.fgDim)
                        .padding(.horizontal, SettingsMetrics.horizontalPadding)
                }
            }
        }
        .confirmationDialog("Delete Custom Provider?", isPresented: deleteDialogBinding, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deletePendingProvider)
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes \(pendingDelete?.id ?? "") from OMP models.yml.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add OpenAI-compatible, Anthropic, Google, Azure, or local discovery providers.")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgMuted)
                Text("Models become available in the Kaji Agent model picker after save.")
                    .kajiFont(size: 10)
                    .foregroundStyle(KajiTheme.fgDim)
            }
            Spacer()
            Button("Refresh") { store.requestCustomProviders() }
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            Button(isEditing ? "Editing" : "Add Provider") { startNew() }
                .buttonStyle(KajiButtonStyle(.primary, size: .small))
                .disabled(isEditing && editingID == nil)
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
    }

    private var emptyState: some View {
        Text("No custom providers yet.")
            .kajiFont(size: SettingsMetrics.labelFontSize)
            .foregroundStyle(KajiTheme.fgDim)
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }

    private var isEditing: Bool {
        isCreating || editingID != nil
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func startNew() {
        draft = KajiAgentCustomProvider()
        editingID = nil
        isCreating = true
        matchedAccountText = ""
    }

    private func edit(_ provider: KajiAgentCustomProvider) {
        draft = provider
        if draft.models.isEmpty { draft.models = [KajiAgentCustomProviderModel()] }
        editingID = provider.id
        isCreating = false
        matchedAccountText = ""
    }

    private func save() {
        guard draft.canSave else { return }
        store.saveCustomProvider(draft) { saved in
            guard saved else { return }
            cancel()
        }
    }

    private func autoMatchModels() {
        guard draft.canAutoMatchModels, !isAutoMatching else { return }
        isAutoMatching = true
        matchedAccountText = ""
        store.previewCustomProviderModels(draft) { result in
            isAutoMatching = false
            guard let result else { return }
            draft.models = result.models.isEmpty ? [KajiAgentCustomProviderModel()] : result.models
            if let accountName = result.accountName, let resourceGroup = result.resourceGroup {
                draft.azureAccountName = accountName
                draft.azureResourceGroup = resourceGroup
                matchedAccountText = "Matched \(accountName) in \(resourceGroup)."
            }
        }
    }

    private func cancel() {
        draft = KajiAgentCustomProvider()
        editingID = nil
        isCreating = false
        isAutoMatching = false
        matchedAccountText = ""
    }

    private func deletePendingProvider() {
        guard let provider = pendingDelete else { return }
        store.deleteCustomProvider(id: provider.id) { _ in }
        pendingDelete = nil
        if editingID == provider.id { cancel() }
    }
}
