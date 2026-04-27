import SwiftUI

struct NotificationRoutesSection: View {
    @State private var integrations = NotificationIntegrationStore.shared
    let onAdd: () -> Void
    let onEdit: (NotificationRoutingRule) -> Void

    var body: some View {
        SettingsSection(
            "Rules",
            footer: "Routes decide which outbound destinations receive each notification source and event type.",
            showsDivider: false
        ) {
            SettingsRow("Manage") {
                Button("Add Rule", action: onAdd)
                    .buttonStyle(DroidButtonStyle(.secondary, size: .small))
            }

            if integrations.routes.isEmpty {
                SettingsRow("Status") {
                    Text("No rules")
                        .droidFont(size: SettingsMetrics.footnoteFontSize)
                        .foregroundStyle(DroidTheme.fgDim)
                }
            } else {
                ForEach(integrations.routes) { route in
                    NotificationRouteRow(
                        route: route,
                        destinationNames: route.destinationIDs.compactMap(destinationName(for:)),
                        onToggle: { enabled in
                            var updated = route
                            updated.isEnabled = enabled
                            integrations.upsertRoute(updated)
                        },
                        onEdit: { onEdit(route) },
                        onDelete: { integrations.removeRoute(route.id) }
                    )
                }
            }
        }
    }

    private func destinationName(for id: UUID) -> String? {
        integrations.destinations.first(where: { $0.id == id })?.name
    }
}
