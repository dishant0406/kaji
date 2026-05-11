import Foundation

enum CodexHooksConfig {
    private static let marker = "kaji-activity-hook"
    private static let obsoleteMarkers = [marker, "muxy-activity-hook"]
    private static let hookEvents = [
        HookEvent(name: "SessionStart", matcher: "startup|resume|clear", action: "start"),
        HookEvent(name: "UserPromptSubmit", matcher: nil, action: "start"),
        HookEvent(name: "PreToolUse", matcher: "*", action: "observe"),
        HookEvent(name: "PermissionRequest", matcher: "*", action: "attention"),
        HookEvent(name: "PostToolUse", matcher: "*", action: "observe"),
        HookEvent(name: "Stop", matcher: nil, action: "stop"),
    ]

    private struct HookEvent {
        let name: String
        let matcher: String?
        let action: String
    }

    static func install(config: String, hooksContent: String, hookClientPath: String) -> (config: String, hooks: String) {
        (
            ensureHooksEnabled(in: config),
            installHooks(in: hooksContent, hookClientPath: hookClientPath)
        )
    }

    static func uninstall(from hooksContent: String) -> String {
        var root = parseRoot(hooksContent)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in hookEvents {
            guard let existing = hooks[event.name] as? [[String: Any]] else { continue }
            let filtered = existing.filter { !isKajiHookEntry($0) }
            if filtered.isEmpty {
                hooks.removeValue(forKey: event.name)
            } else {
                hooks[event.name] = filtered
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

        for event in hookEvents {
            hooks[event.name] = merge(
                entries: hooks[event.name] as? [[String: Any]],
                matcher: event.matcher,
                command: hookCommand(hookClientPath: hookClientPath, providerID: "codex", action: event.action)
            )
        }

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
            let obsoleteIndices = lines[(featuresIndex + 1) ..< sectionEnd].indices.filter {
                lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("codex_hooks")
            }
            for index in obsoleteIndices.reversed() {
                lines.remove(at: index)
            }
            let updatedSectionEnd = lines[(featuresIndex + 1)...].firstIndex {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
            } ?? lines.endIndex
            if let settingIndex = lines[(featuresIndex + 1) ..< updatedSectionEnd].firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("hooks")
            }) {
                lines[settingIndex] = "hooks = true"
            } else {
                lines.insert("hooks = true", at: featuresIndex + 1)
            }
            return normalizedText(lines)
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "[features]\nhooks = true\n"
        }
        return trimmed + "\n\n[features]\nhooks = true\n"
    }

    private static func parseRoot(_ content: String) -> [String: Any] {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    private static func merge(entries: [[String: Any]]?, matcher: String?, command: String) -> [[String: Any]] {
        var merged = entries ?? []
        merged.removeAll { isKajiHookEntry($0) }
        var entry: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": command,
                    "timeout": 5,
                ],
            ],
        ]
        if let matcher {
            entry["matcher"] = matcher
        }
        merged.append(entry)
        return merged
    }

    private static func isKajiHookEntry(_ entry: [String: Any]) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return obsoleteMarkers.contains { command.contains($0) }
        }
    }

    private static func hookCommand(hookClientPath: String, providerID: String, action: String) -> String {
        let fallbackPath = ShellEscaper.escape(hookClientPath)
        return [
            "if [ -x \(fallbackPath) ]; then",
            "\(fallbackPath) codex-activity \(providerID) \(action);",
            "elif [ -n \"${KAJI_HOOK_CLIENT_PATH:-}\" ] && [ -x \"$KAJI_HOOK_CLIENT_PATH\" ]; then",
            "\"$KAJI_HOOK_CLIENT_PATH\" codex-activity \(providerID) \(action);",
            "fi # \(marker)",
        ].joined(separator: " ")
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
