import SwiftUI

struct NotificationDestinationModal: View {
    let existing: NotificationDeliveryDestination?
    let onCancel: () -> Void
    let onSave: (NotificationDeliveryDestination, String) -> Void
    @State private var draft: NotificationDeliveryDestination
    @State private var bearerToken: String
    @State private var testMessage: String?
    @State private var errorMessage: String?
    @State private var sendingTest = false

    init(
        existing: NotificationDeliveryDestination?,
        bearerToken: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (NotificationDeliveryDestination, String) -> Void
    ) {
        self.existing = existing
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: existing ?? NotificationDestinationPresetFactory.make(type: .ntfy))
        _bearerToken = State(initialValue: bearerToken)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DroidTheme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    form
                    preview
                    if let message = errorMessage ?? testMessage {
                        Text(message)
                            .droidFont(size: 11)
                            .foregroundStyle(errorMessage == nil ? DroidTheme.fgDim : DroidTheme.diffRemoveFg)
                    }
                }
                .padding(18)
            }
            Divider().overlay(DroidTheme.border)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DroidTheme.bg.opacity(0.34))
    }

    private var header: some View {
        HStack {
            Text(existing == nil ? "New Destination" : "Edit Destination")
                .droidFont(size: 13, weight: .semibold)
                .foregroundStyle(DroidTheme.fg)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DroidTheme.chrome.opacity(0.42))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            NotificationFormRow("Name") {
                DroidInput(placeholder: "Ops ntfy", text: $draft.name)
            }
            NotificationFormRow("Type") {
                DroidSelect(
                    options: NotificationDestinationType.allCases.map {
                        DroidSelectOption(id: $0.rawValue, title: $0.rawValue, value: $0)
                    },
                    selection: $draft.type,
                    width: 220
                )
                .onChange(of: draft.type) { _, newValue in
                    applyPreset(newValue)
                }
            }
            NotificationFormRow("Endpoint") {
                DroidInput(placeholder: "https://example.com/hook", text: $draft.endpointURL, width: 420, monospaced: true)
            }
            HStack(alignment: .top, spacing: 12) {
                NotificationFormRow("Method") {
                    DroidSelect(
                        options: NotificationRequestMethod.allCases.map {
                            DroidSelectOption(id: $0.rawValue, title: $0.rawValue, value: $0)
                        },
                        selection: $draft.method,
                        width: 140
                    )
                }
                NotificationFormRow("Content Type") {
                    DroidSelect(
                        options: NotificationPayloadContentType.allCases.map {
                            DroidSelectOption(id: $0.rawValue, title: $0.label, value: $0)
                        },
                        selection: $draft.contentType,
                        width: 200
                    )
                }
            }
            NotificationFormRow("Bearer Token") {
                DroidInput(placeholder: "Optional", text: $bearerToken, width: 420, monospaced: true)
            }
            NotificationFormBlock("Headers") {
                DroidTextArea(placeholder: "Header-Name: value", text: $draft.headersTemplate, minHeight: 90, monospaced: true)
            }
            NotificationFormBlock("Body Template") {
                DroidTextArea(placeholder: "{{body}}", text: $draft.bodyTemplate, minHeight: 160, monospaced: true)
            }
        }
    }

    private var preview: some View {
        NotificationFormBlock("Preview") {
            ScrollView {
                Text(NotificationTemplateRenderer.render(draft.bodyTemplate, event: .sample))
                    .droidFont(size: 12, design: .monospaced)
                    .foregroundStyle(DroidTheme.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 100)
            .background(DroidTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: DroidShape.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DroidShape.controlRadius).stroke(DroidTheme.border, lineWidth: 1))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(DroidButtonStyle(.secondary))
            Button(sendingTest ? "Sending..." : "Send Test") {
                sendTest()
            }
            .buttonStyle(DroidButtonStyle(.secondary))
            .disabled(sendingTest || !canSave)
            Button(existing == nil ? "Create" : "Save") {
                onSave(draft, bearerToken)
            }
            .buttonStyle(DroidButtonStyle(.primary))
            .disabled(!canSave)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DroidTheme.chrome.opacity(0.42))
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.endpointURL
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyPreset(_ type: NotificationDestinationType) {
        let preset = NotificationDestinationPresetFactory.make(type: type, id: draft.id)
        draft.type = preset.type
        draft.method = preset.method
        draft.contentType = preset.contentType
        draft.headersTemplate = preset.headersTemplate
        draft.bodyTemplate = preset.bodyTemplate
        if draft.name.isEmpty
            || draft.name == existing?.name
            || NotificationDestinationType.allCases.map(\.rawValue).contains(draft.name)
        {
            draft.name = preset.name
        }
        if draft.endpointURL.isEmpty || draft.endpointURL == existing?.endpointURL {
            draft.endpointURL = preset.endpointURL
        }
    }

    private func sendTest() {
        errorMessage = nil
        testMessage = nil
        sendingTest = true
        Task {
            do {
                try await NotificationEndpointSender().send(destination: draft, bearerToken: bearerToken, event: .sample)
                await MainActor.run {
                    sendingTest = false
                    testMessage = "Test notification sent."
                }
            } catch {
                await MainActor.run {
                    sendingTest = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
