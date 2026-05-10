import SwiftUI

struct MCPServerEditorView: View {
    @State var state: MCPServerEditorState
    let onCancel: () -> Void
    let onSave: (MCPServerEditorState) -> Void

    @State private var argumentsText = ""
    @State private var environmentText = ""
    @State private var headersText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DroidTheme.border)
            form
            Divider().overlay(DroidTheme.border)
            footer
        }
        .onAppear(perform: hydrateTextFields)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.originalName == nil ? "Add MCP Server" : "Edit MCP Server")
                    .droidFont(size: 15, weight: .semibold)
                    .foregroundStyle(DroidTheme.fg)
                Text("Use KEY=value lines for environment and headers.")
                    .droidFont(size: 11)
                    .foregroundStyle(DroidTheme.fgDim)
            }
            Spacer(minLength: 0)
            IconButton(symbol: "xmark", accessibilityLabel: "Cancel MCP Server Edit", action: onCancel)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                field("Name") {
                    DroidInput(placeholder: "filesystem", text: $state.server.name, width: 360, monospaced: true)
                }

                if state.server.transport == .plugin {
                    Text("Plugin servers are managed by the agent marketplace or plugin settings.")
                        .droidFont(size: 12)
                        .foregroundStyle(DroidTheme.fgDim)
                } else {
                    field("Transport") {
                        SegmentedPicker(
                            selection: $state.server.transport,
                            options: [.stdio, .remote].map { ($0, $0.title) }
                        )
                        .frame(width: 220)
                    }
                }
                if state.server.transport == .stdio {
                    field("Command") {
                        DroidInput(placeholder: "npx", text: $state.server.command, width: 360, monospaced: true)
                    }
                    field("Arguments") {
                        DroidTextArea(
                            placeholder: "-y @modelcontextprotocol/server-filesystem /tmp",
                            text: $argumentsText,
                            minHeight: 74,
                            monospaced: true
                        )
                        .frame(height: 74)
                    }
                    field("Environment") {
                        DroidTextArea(placeholder: "API_KEY=$API_KEY", text: $environmentText, minHeight: 92, monospaced: true)
                            .frame(height: 92)
                    }
                } else if state.server.transport == .remote {
                    field("URL") {
                        DroidInput(placeholder: "https://example.com/mcp", text: $state.server.url, width: 440, monospaced: true)
                    }
                    field("Headers") {
                        DroidTextArea(
                            placeholder: "Authorization=Bearer ${env:API_TOKEN}",
                            text: $headersText,
                            minHeight: 92,
                            monospaced: true
                        )
                        .frame(height: 92)
                    }
                    field("Bearer Token Env") {
                        DroidInput(placeholder: "API_TOKEN", text: bearerBinding, width: 260, monospaced: true)
                    }
                }
                if state.server.transport != .plugin {
                    Toggle("Direct tools", isOn: $state.server.directTools)
                        .toggleStyle(.checkbox)
                        .droidFont(size: 12)
                        .foregroundStyle(DroidTheme.fg)
                }
                Toggle("Enabled", isOn: $state.server.enabled)
                    .toggleStyle(.checkbox)
                    .droidFont(size: 12)
                    .foregroundStyle(DroidTheme.fg)
            }
            .padding(18)
        }
    }

    private var footer: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Cancel", action: onCancel)
                .buttonStyle(DroidButtonStyle(.secondary, size: .small))
            Button("Save") {
                state.server.arguments = shellSplit(argumentsText)
                state.server.environment = keyValueMap(environmentText)
                state.server.headers = keyValueMap(headersText)
                onSave(state)
            }
            .buttonStyle(DroidButtonStyle(.primary, size: .small))
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .droidFont(size: 11, weight: .semibold)
                .foregroundStyle(DroidTheme.fgDim)
            content()
        }
    }

    private var bearerBinding: Binding<String> {
        Binding(
            get: { state.server.bearerTokenEnvVar ?? "" },
            set: { state.server.bearerTokenEnvVar = $0.isEmpty ? nil : $0 }
        )
    }

    private func hydrateTextFields() {
        argumentsText = state.server.arguments.map(shellQuoteIfNeeded).joined(separator: " ")
        environmentText = keyValueText(state.server.environment)
        headersText = keyValueText(state.server.headers)
    }

    private func keyValueText(_ values: [String: String]) -> String {
        values.keys.sorted().map { "\($0)=\(values[$0] ?? "")" }.joined(separator: "\n")
    }

    private func keyValueMap(_ text: String) -> [String: String] {
        text.components(separatedBy: .newlines).reduce(into: [String: String]()) { result, line in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return }
            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            result[key] = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func shellQuoteIfNeeded(_ value: String) -> String {
        value.contains(" ") ? "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\"" : value
    }

    private func shellSplit(_ value: String) -> [String] {
        var result = [String]()
        var current = ""
        var quote: Character?
        var escaping = false
        for character in value {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if character == "\\" {
                escaping = true
                continue
            }
            if character == "\"" || character == "'" {
                if quote == character { quote = nil } else if quote == nil { quote = character } else { current.append(character) }
                continue
            }
            if character.isWhitespace, quote == nil {
                if !current.isEmpty { result.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
