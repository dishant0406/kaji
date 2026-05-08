import Foundation

enum CodexHooksConfig {
    private static let marker = "droid-activity-hook"
    private static let obsoleteMarkers = [marker, "muxy-activity-hook"]

    static func install(config: String, hooksContent: String, hookClientPath: String) -> (config: String, hooks: String) {
        (
            ensureHooksEnabled(in: config),
            installHooks(in: hooksContent, hookClientPath: hookClientPath)
        )
    }

    static func uninstall(from hooksContent: String) -> String {
        var root = parseRoot(hooksContent)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in ["SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest"] {
            guard let existing = hooks[event] as? [[String: Any]] else { continue }
            let filtered = existing.filter { !isDroidHookEntry($0) }
            if filtered.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = filtered
            }
        }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        return normalizedJSON(root)
    }

    private static func installHooks(in content: String, hookClientPath: String) -> String {
        var root = parseRoot(content)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        hooks["SessionStart"] = merge(
            entries: hooks["SessionStart"] as? [[String: Any]],
            command: hookCommand(hookClientPath: hookClientPath, providerID: "codex", state: "start")
        )
        hooks["UserPromptSubmit"] = merge(
            entries: hooks["UserPromptSubmit"] as? [[String: Any]],
            command: hookCommand(hookClientPath: hookClientPath, providerID: "codex", state: "start")
        )
        hooks["Stop"] = merge(
            entries: hooks["Stop"] as? [[String: Any]],
            command: hookCommand(hookClientPath: hookClientPath, providerID: "codex", state: "stop")
        )
        hooks["PermissionRequest"] = merge(
            entries: hooks["PermissionRequest"] as? [[String: Any]],
            command: hookCommand(hookClientPath: hookClientPath, providerID: "codex", state: "attention")
        )

        root["hooks"] = hooks
        return normalizedJSON(root)
    }

    private static func ensureHooksEnabled(in content: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        if let featuresIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
            let sectionEnd = lines[(featuresIndex + 1)...].firstIndex {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
            } ?? lines.endIndex
            if let settingIndex = lines[(featuresIndex + 1) ..< sectionEnd].firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("codex_hooks")
            }) {
                lines[settingIndex] = "codex_hooks = true"
            } else {
                lines.insert("codex_hooks = true", at: featuresIndex + 1)
            }
            return normalizedText(lines)
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "[features]\ncodex_hooks = true\n"
        }
        return trimmed + "\n\n[features]\ncodex_hooks = true\n"
    }

    private static func parseRoot(_ content: String) -> [String: Any] {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    private static func merge(entries: [[String: Any]]?, command: String) -> [[String: Any]] {
        var merged = entries ?? []
        merged.removeAll { isDroidHookEntry($0) }
        merged.append([
            "hooks": [
                [
                    "type": "command",
                    "command": command,
                ],
            ],
        ])
        return merged
    }

    private static func isDroidHookEntry(_ entry: [String: Any]) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return obsoleteMarkers.contains { command.contains($0) }
        }
    }

    private static func hookCommand(hookClientPath: String, providerID: String, state: String) -> String {
        "\(ShellEscaper.escape(hookClientPath)) codex-activity \(providerID) \(state) # \(marker)"
    }

    private static func normalizedJSON(_ root: [String: Any]) -> String {
        guard !root.isEmpty else { return "" }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return text + "\n"
    }

    private static func normalizedText(_ lines: [String]) -> String {
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "" : text + "\n"
    }
}
