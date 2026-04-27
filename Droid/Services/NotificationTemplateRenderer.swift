import Foundation

enum NotificationTemplateRenderer {
    static func render(_ template: String, event: NotificationOutboundEvent) -> String {
        event.templateValues.reduce(template) { partial, entry in
            partial.replacingOccurrences(of: "{{\(entry.key)}}", with: entry.value)
        }
    }
}
