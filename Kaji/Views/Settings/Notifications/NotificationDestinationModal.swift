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
            Divider().overlay(KajiTheme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    form
                    preview
                    if let message = errorMessage ?? testMessage {
                        Text(message)
                            .kajiFont(size: 11)
                            .foregroundStyle(errorMessage == nil ? KajiTheme.fgDim : KajiTheme.diffRemoveFg)
                    }
                }
                .padding(18)
            }
            Divider().overlay(KajiTheme.border)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KajiTheme.bg.opacity(0.34))
    }

    private var header: some View {
        HStack {
            Text(existing == nil ? "New Destination" : "Edit Destination")
                .kajiFont(size: 13, weight: .semibold)
                .foregroundStyle(KajiTheme.fg)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(KajiTheme.chrome.opacity(0.42))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            NotificationFormRow("Name") {
                KajiInput(placeholder: "Ops ntfy", text: $draft.name)
            }
            NotificationFormRow("Type") {
                KajiSelect(
                    options: NotificationDestinationType.allCases.map {
                        KajiSelectOption(id: $0.rawValue, title: $0.rawValue, value: $0)
                    },
                    selection: $draft.type,
                    width: 220
                )
                .onChange(of: draft.type) { _, newValue in
                    applyPreset(newValue)
                }
            }
            NotificationFormRow("Endpoint") {
                KajiInput(placeholder: "https://example.com/hook", text: $draft.endpointURL, width: 420, monospaced: true)
            }
            HStack(alignment: .top, spacing: 12) {
                NotificationFormRow("Method") {
                    KajiSelect(
                        options: NotificationRequestMethod.allCases.map {
                            KajiSelectOption(id: $0.rawValue, title: $0.rawValue, value: $0)
                        },
                        selection: $draft.method,
                        width: 140
                    )
                }
                NotificationFormRow("Content Type") {
                    KajiSelect(
                        options: NotificationPayloadContentType.allCases.map {
                            KajiSelectOption(id: $0.rawValue, title: $0.label, value: $0)
                        },
                        selection: $draft.contentType,
                        width: 200
                    )
                }
            }
            NotificationFormRow("Bearer Token") {
                KajiInput(placeholder: "Optional", text: $bearerToken, width: 420, monospaced: true)
            }
            NotificationFormBlock("Headers") {
                KajiTextArea(placeholder: "Header-Name: value", text: $draft.headersTemplate, minHeight: 90, monospaced: true)
            }
            NotificationFormBlock("Body Template") {
                KajiTextArea(placeholder: "{{body}}", text: $draft.bodyTemplate, minHeight: 160, monospaced: true)
            }
        }
    }

    private var preview: some View {
        NotificationFormBlock("Preview") {
            ScrollView {
                Text(NotificationTemplateRenderer.render(draft.bodyTemplate, event: .sample))
                    .kajiFont(size: 12, design: .monospaced)
                    .foregroundStyle(KajiTheme.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 100)
            .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: KajiShape.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: KajiShape.controlRadius).stroke(KajiTheme.border, lineWidth: 1))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(KajiButtonStyle(.secondary))
            Button(sendingTest ? "Sending..." : "Send Test") {
                sendTest()
            }
            .buttonStyle(KajiButtonStyle(.secondary))
            .disabled(sendingTest || !canSave)
            Button(existing == nil ? "Create" : "Save") {
                onSave(draft, bearerToken)
            }
            .buttonStyle(KajiButtonStyle(.primary))
            .disabled(!canSave)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(KajiTheme.chrome.opacity(0.42))
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
