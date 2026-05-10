import Foundation

enum CodexBrowserMCPConfig {
    static func arguments(for descriptor: DroidBrowserMCPServerDescriptor) -> [String] {
        let values = [
            "mcp_servers.\(descriptor.name).command=\"\(escape(descriptor.command))\"",
            "mcp_servers.\(descriptor.name).args=\(array(descriptor.arguments))",
            "mcp_servers.\(descriptor.name).env=\(environmentTable(descriptor.environment))",
        ]
        return values.flatMap { ["-c", $0] }
    }

    static func shellArguments(for descriptor: DroidBrowserMCPServerDescriptor) -> String {
        arguments(for: descriptor).map(ShellEscaper.escape).joined(separator: " ")
    }

    private static func array(_ values: [String]) -> String {
        "[" + values.map { "\"\(escape($0))\"" }.joined(separator: ", ") + "]"
    }

    private static func environmentTable(_ values: [String: String]) -> String {
        let pairs = values.keys.sorted().map { key in
            "\(key)=\"\(escape(values[key] ?? ""))\""
        }
        return "{" + pairs.joined(separator: ", ") + "}"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
