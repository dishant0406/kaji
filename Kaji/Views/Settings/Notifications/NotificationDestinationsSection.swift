import SwiftUI

struct NotificationDestinationsSection: View {
    @State private var integrations = NotificationIntegrationStore.shared
    let onAdd: () -> Void
    let onEdit: (NotificationDeliveryDestination) -> Void

    var body: some View {
        SettingsSection(
            "Destinations",
            footer: "Create HTTP destinations like ntfy and custom webhooks. "
                + "Tokens: {{title}}, {{body}}, {{source}}, {{event_kind}}, "
                + "{{project}}, {{worktree}}, {{timestamp_iso}}."
        ) {
            SettingsRow("Manage") {
                Button("Add Destination", action: onAdd)
                    .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            }

            if integrations.destinations.isEmpty {
                SettingsRow("Status") {
                    Text("No destinations")
                        .kajiFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(KajiTheme.fgDim)
                }
            } else {
                ForEach(integrations.destinations) { destination in
                    NotificationDestinationRow(
                        destination: destination,
                        onToggle: { enabled in
                            var updated = destination
                            updated.isEnabled = enabled
                            integrations.upsertDestination(updated, bearerToken: integrations.bearerToken(for: destination.id))
                        },
                        onEdit: { onEdit(destination) },
                        onDelete: { integrations.removeDestination(destination.id) },
                        onTest: {
                            do {
                                try await integrations.sendTest(to: destination)
                                return nil
                            } catch {
                                return error.localizedDescription
                            }
                        }
                    )
                }
            }
        }
    }
}
