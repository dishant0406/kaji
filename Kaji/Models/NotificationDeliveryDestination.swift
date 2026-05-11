import Foundation

struct NotificationDeliveryDestination: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: NotificationDestinationType
    var endpointURL: String
    var method: NotificationRequestMethod
    var contentType: NotificationPayloadContentType
    var headersTemplate: String
    var bodyTemplate: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        type: NotificationDestinationType,
        endpointURL: String,
        method: NotificationRequestMethod,
        contentType: NotificationPayloadContentType,
        headersTemplate: String,
        bodyTemplate: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.endpointURL = endpointURL
        self.method = method
        self.contentType = contentType
        self.headersTemplate = headersTemplate
        self.bodyTemplate = bodyTemplate
        self.isEnabled = isEnabled
    }
}
