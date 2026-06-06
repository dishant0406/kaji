import SwiftUI

struct KajiAgentControlPanel: View {
    let panel: KajiAgentPanel
    @Bindable var store: KajiAgentStore
    let onClose: () -> Void
    @State private var bashCommand = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                KajiIcon(systemName: icon, size: 12)
                    .foregroundStyle(KajiTheme.fgMuted)
                Text(title)
                    .kajiFont(size: 12, weight: .semibold)
                    .foregroundStyle(KajiTheme.fg)
                Spacer(minLength: 0)
                Button("Close", action: onClose)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
            content
        }
        .padding(12)
        .frame(maxWidth: 720, alignment: .leading)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var content: some View {
        switch panel {
        case .models:
            searchableModels
        case .login:
            optionList(store.loginProviders) { provider in
                Button { store.login(providerID: provider.id) } label: {
                    row(
                        title: provider.name,
                        detail: provider.authenticated ? "Connected" : "Not connected",
                        icon: provider.authenticated ? "checkmark.circle" : "person.badge.key"
                    )
                }
                .buttonStyle(.plain)
            }
        case .tools:
            optionList(store.toolOptions) { tool in
                Button {
                    var names = Set(store.toolOptions.filter(\.isActive).map(\.name))
                    if tool.isActive { names.remove(tool.name) } else { names.insert(tool.name) }
                    store.setActiveTools(Array(names).sorted())
                } label: {
                    row(title: tool.name, detail: tool.detail, icon: tool.isActive ? "checkmark.square" : "square")
                }
                .buttonStyle(.plain)
            }
        case .sessions:
            searchableSessions
        }
    }

    private var searchableModels: some View {
        SearchableListPicker(
            items: store.modelOptions,
            filterKey: { "\($0.title) \($0.provider) \($0.modelID) \($0.id)" },
            placeholder: "Search models",
            emptyLabel: "No models",
            emptyActionTitle: nil,
            emptyActionDetail: nil,
            onEmptyAction: nil,
            onSelect: { option in
                store.setModel(provider: option.provider, modelID: option.modelID)
                onClose()
            },
            row: { option, highlighted in
                row(title: option.title, detail: option.id, icon: highlighted ? "checkmark.circle" : "sparkles")
            }
        )
        .frame(maxHeight: 320)
    }

    private var searchableSessions: some View {
        SearchableListPicker(
            items: store.sessionOptions,
            filterKey: { "\($0.title) \($0.detail) \($0.path)" },
            placeholder: "Search sessions",
            emptyLabel: "No sessions",
            emptyActionTitle: nil,
            emptyActionDetail: nil,
            onEmptyAction: nil,
            onSelect: { session in
                store.switchSession(path: session.path)
                onClose()
            },
            row: { session, highlighted in
                row(title: session.title, detail: session.detail, icon: highlighted ? "checkmark.circle" : "square.stack")
            }
        )
        .frame(maxHeight: 320)
    }

    private func optionList<Data: RandomAccessCollection>(
        _ data: Data,
        @ViewBuilder rowBuilder: @escaping (Data.Element) -> some View
    ) -> some View where Data.Element: Identifiable {
        ScrollView(.vertical, showsIndicators: data.count > 5) {
            LazyVStack(spacing: 4) {
                ForEach(Array(data), id: \.id) { item in
                    rowBuilder(item)
                }
                if data.isEmpty {
                    Text("No options loaded yet")
                        .kajiFont(size: 12)
                        .foregroundStyle(KajiTheme.fgDim)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private func row(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 10) {
            KajiIcon(systemName: icon, size: 12)
                .foregroundStyle(KajiTheme.fgMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .kajiFont(size: 12, weight: .medium)
                    .foregroundStyle(KajiTheme.fg)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .kajiFont(size: 11)
                        .foregroundStyle(KajiTheme.fgDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(KajiTheme.bg.opacity(0.56), in: RoundedRectangle(cornerRadius: 10))
        .kajiPointer()
    }

    private var title: String {
        switch panel {
        case .models: "Models"
        case .login: "Login providers"
        case .tools: "Tools"
        case .sessions: "Sessions"
        }
    }

    private var icon: String {
        switch panel {
        case .models: "sparkles"
        case .login: "person.badge.key"
        case .tools: "wrench.and.screwdriver"
        case .sessions: "square.stack"
        }
    }
}
