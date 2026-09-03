import SwiftUI

struct AIGatewayModelsSection: View {
    let models: [AIGatewayModelAlias]
    let onUpdate: (AIGatewayModelAlias, Int) -> Void
    let onDelete: (Int) -> Void
    let onAdd: () -> Void

    var body: some View {
        SettingsSection("Models & Routing", footer: "Routes use provider/model-id. Multiple lines create a pre-stream fallback chain.") {
            ForEach(Array(models.enumerated()), id: \.offset) { index, model in
                AIGatewayModelRow(
                    model: model,
                    index: index,
                    canDelete: models.count > 1,
                    isLast: index == models.count - 1,
                    onUpdate: onUpdate,
                    onDelete: { onDelete(index) }
                )
            }
            HStack {
                Spacer(minLength: 0)
                Button("Add Model", action: onAdd)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }
            .padding(.horizontal, SettingsMetrics.horizontalPadding)
            .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
        }
    }
}

private struct AIGatewayModelRow: View {
    let model: AIGatewayModelAlias
    let index: Int
    let canDelete: Bool
    let isLast: Bool
    let onUpdate: (AIGatewayModelAlias, Int) -> Void
    let onDelete: () -> Void
    @State private var alias: String
    @State private var displayName: String
    @State private var routesText: String
    @State private var exposeClaude: Bool
    @State private var exposeCodex: Bool

    init(
        model: AIGatewayModelAlias,
        index: Int,
        canDelete: Bool,
        isLast: Bool,
        onUpdate: @escaping (AIGatewayModelAlias, Int) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.model = model
        self.index = index
        self.canDelete = canDelete
        self.isLast = isLast
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _alias = State(initialValue: model.alias)
        _displayName = State(initialValue: model.displayName)
        _routesText = State(initialValue: model.routes.joined(separator: "\n"))
        _exposeClaude = State(initialValue: model.exposeClaude)
        _exposeCodex = State(initialValue: model.exposeCodex)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                KajiInput(placeholder: "alias", text: $alias, width: 130, monospaced: true)
                KajiInput(placeholder: "Display name", text: $displayName)
                if canDelete {
                    Button("Delete", action: onDelete)
                        .buttonStyle(KajiButtonStyle(.secondary, size: .small))
                }
            }
            HStack(alignment: .top, spacing: 8) {
                KajiTextArea(placeholder: "ollama/qwen2.5-coder:latest", text: $routesText, minHeight: 58, maxHeight: 92, monospaced: true)
                VStack(alignment: .leading, spacing: 8) {
                    toggle("Claude", isOn: $exposeClaude)
                    toggle("Codex", isOn: $exposeCodex)
                    Button("Save", action: commit)
                        .buttonStyle(KajiButtonStyle(.primary, size: .small))
                }
                .frame(width: 92, alignment: .topLeading)
            }
            if !isLast {
                Divider()
            }
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding + 4)
        .onChange(of: model) { _, value in sync(value) }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            KajiSwitch(isOn: isOn)
            Text(title)
                .kajiFont(size: SettingsMetrics.footnoteFontSize)
                .foregroundStyle(KajiTheme.fgMuted)
        }
    }

    private func commit() {
        let routes = routesText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        onUpdate(AIGatewayModelAlias(
            alias: alias,
            displayName: displayName,
            routes: routes,
            exposeClaude: exposeClaude,
            exposeCodex: exposeCodex
        ), index)
    }

    private func sync(_ model: AIGatewayModelAlias) {
        alias = model.alias
        displayName = model.displayName
        routesText = model.routes.joined(separator: "\n")
        exposeClaude = model.exposeClaude
        exposeCodex = model.exposeCodex
    }
}
