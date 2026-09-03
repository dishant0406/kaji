import Foundation

struct KajiAgentToolRenderDescriptor: Hashable {
    let iconName: String
    let title: String
    let subtitle: String
    let argumentPreview: String?
}

enum KajiAgentToolRenderer {
    static func descriptor(for message: KajiAgentMessage) -> KajiAgentToolRenderDescriptor {
        let name = message.title
        let args = message.toolArguments ?? ""
        let preview = compactArguments(args)
        return KajiAgentToolRenderDescriptor(
            iconName: iconName(for: name),
            title: title(for: name, args: args),
            subtitle: subtitle(for: message),
            argumentPreview: preview
        )
    }

    private static func title(for name: String, args: String) -> String {
        let lower = name.lowercased()
        if lower == "bash", let command = value(named: "command", in: args) {
            return command
        }
        if ["edit", "multi_edit", "write", "read"].contains(lower), let path = filePath(in: args) {
            return path
        }
        if lower == "todo_write" {
            return "Update task plan"
        }
        if lower == "task" {
            return "Run subagent task"
        }
        return name
    }

    private static func subtitle(for message: KajiAgentMessage) -> String {
        if message.isError {
            return "Failed"
        }
        if !message.isComplete {
            return message.preview == nil ? "Running" : "Streaming output"
        }
        if message.taskDetails != nil {
            return "Task details"
        }
        return message.kajiAgentToolOutput == nil ? "Completed" : "Output available"
    }

    private static func iconName(for name: String) -> String {
        switch name.lowercased() {
        case "bash": "terminal"
        case "edit",
             "multi_edit",
             "write": "square.and.pencil"
        case "read": "doc.text.magnifyingglass"
        case "task": "person.2"
        case "todo_write",
             "todo_read": "checklist"
        default: "wrench.and.screwdriver"
        }
    }

    private static func compactArguments(_ args: String) -> String? {
        let value = args.replacingOccurrences(of: "\n", with: "  ").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func filePath(in args: String) -> String? {
        value(named: "file_path", in: args) ?? value(named: "path", in: args) ?? value(named: "file", in: args)
    }

    private static func value(named name: String, in args: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            "\\\"\(escaped)\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            "\(escaped)\\s*[:=]\\s*([^,}]+)",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(args.startIndex..., in: args)
            guard let match = regex.firstMatch(in: args, range: range),
                  let valueRange = Range(match.range(at: 1), in: args)
            else { continue }
            return String(args[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
