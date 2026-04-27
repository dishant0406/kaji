import Foundation
import os

private let notificationIntegrationLogger = Logger(subsystem: "app.droid", category: "NotificationIntegrationStore")

@MainActor
@Observable
final class NotificationIntegrationStore {
    static let shared = NotificationIntegrationStore()

    private(set) var settings: NotificationIntegrationSettings

    @ObservationIgnored private let fileStore: CodableFileStore<NotificationIntegrationSettings>
    @ObservationIgnored private let secretStore: NotificationSecretStore
    @ObservationIgnored private let sender: NotificationEndpointSender

    init(
        fileStore: CodableFileStore<NotificationIntegrationSettings> = .init(
            fileURL: DroidFileStorage.fileURL(filename: "notification-integrations.json"),
            options: .prettySorted
        ),
        secretStore: NotificationSecretStore = .init(),
        sender: NotificationEndpointSender = .init()
    ) {
        self.fileStore = fileStore
        self.secretStore = secretStore
        self.sender = sender
        settings = (try? fileStore.load()) ?? .empty
    }

    var destinations: [NotificationDeliveryDestination] { settings.destinations }
    var routes: [NotificationRoutingRule] { settings.routes }

    func bearerToken(for destinationID: UUID) -> String {
        secretStore.loadBearerToken(for: destinationID)
    }

    func upsertDestination(_ destination: NotificationDeliveryDestination, bearerToken: String) {
        if let index = settings.destinations.firstIndex(where: { $0.id == destination.id }) {
            settings.destinations[index] = destination
        } else {
            settings.destinations.append(destination)
        }
        secretStore.saveBearerToken(bearerToken, for: destination.id)
        save()
    }

    func removeDestination(_ destinationID: UUID) {
        settings.destinations.removeAll { $0.id == destinationID }
        settings.routes = settings.routes.map {
            var route = $0
            route.destinationIDs.removeAll { $0 == destinationID }
            return route
        }
        secretStore.deleteBearerToken(for: destinationID)
        save()
    }

    func upsertRoute(_ route: NotificationRoutingRule) {
        if let index = settings.routes.firstIndex(where: { $0.id == route.id }) {
            settings.routes[index] = route
        } else {
            settings.routes.append(route)
        }
        save()
    }

    func removeRoute(_ routeID: UUID) {
        settings.routes.removeAll { $0.id == routeID }
        save()
    }

    func previewBody(
        for destination: NotificationDeliveryDestination,
        event: NotificationOutboundEvent = .sample
    ) -> String {
        NotificationTemplateRenderer.render(destination.bodyTemplate, event: event)
    }

    func sendTest(to destination: NotificationDeliveryDestination) async throws {
        try await sender.send(
            destination: destination,
            bearerToken: secretStore.loadBearerToken(for: destination.id),
            event: .sample
        )
    }

    func deliver(_ event: NotificationOutboundEvent) async {
        let routedDestinations = matchingDestinations(for: event)
        for destination in routedDestinations {
            do {
                try await sender.send(
                    destination: destination,
                    bearerToken: secretStore.loadBearerToken(for: destination.id),
                    event: event
                )
            } catch {
                notificationIntegrationLogger.error("Failed to deliver outbound notification: \(error.localizedDescription)")
            }
        }
    }

    private func matchingDestinations(for event: NotificationOutboundEvent) -> [NotificationDeliveryDestination] {
        let activeDestinationIDs = Set(settings.routes.filter { $0.matches(event) }.flatMap(\.destinationIDs))
        return settings.destinations.filter { $0.isEnabled && activeDestinationIDs.contains($0.id) }
    }

    private func save() {
        do {
            try fileStore.save(settings)
        } catch {
            notificationIntegrationLogger.error("Failed to save notification integrations: \(error.localizedDescription)")
        }
    }
}
