import Foundation

enum NotificationDestinationPresetFactory {
    static func make(type: NotificationDestinationType, id: UUID = UUID()) -> NotificationDeliveryDestination {
        switch type {
        case .ntfy:
            NotificationDeliveryDestination(
                id: id,
                name: "ntfy",
                type: .ntfy,
                endpointURL: "https://ntfy.sh/topic-name",
                method: .post,
                contentType: .plainText,
                headersTemplate: "Title: {{title}}",
                bodyTemplate: "{{body}}"
            )
        case .webhook:
            NotificationDeliveryDestination(
                id: id,
                name: "Webhook",
                type: .webhook,
                endpointURL: "https://example.com/hooks/droid",
                method: .post,
                contentType: .json,
                headersTemplate: "",
                bodyTemplate: [
                    "{",
                    "  \"source\": \"{{source}}\",",
                    "  \"event\": \"{{event_kind}}\",",
                    "  \"title\": \"{{title}}\",",
                    "  \"body\": \"{{body}}\",",
                    "  \"project\": \"{{project}}\",",
                    "  \"worktree\": \"{{worktree}}\",",
                    "  \"timestamp\": \"{{timestamp_iso}}\"",
                    "}",
                ]
                .joined(separator: "\n")
            )
        }
    }
}
