import Foundation

enum ThemeFileCodec {
    private static let namePrefix = "# droid-name:"
    private static let slugPrefix = "# droid-slug:"

    static func parseThemeFile(
        at url: URL,
        source: ThemePreview.Source,
        identifierOverride: String? = nil
    ) -> ThemePreview? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let identifier = identifierOverride ?? url.deletingPathExtension().lastPathComponent
        return parseThemeContent(content, identifier: identifier, source: source)
    }

    static func parseThemeContent(
        _ content: String,
        identifier: String,
        source: ThemePreview.Source
    ) -> ThemePreview? {
        var parsedName: String?
        var parsedSlug: String?
        var values: [String: String] = [:]
        var palette = [String?](repeating: nil, count: 16)

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(namePrefix) {
                parsedName = String(line.dropFirst(namePrefix.count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix(slugPrefix) {
                parsedSlug = String(line.dropFirst(slugPrefix.count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("palette") {
                parsePalette(line, into: &palette)
                continue
            }
            parseValue(line, into: &values)
        }

        guard let background = normalizeHex(values["background"]),
              let foreground = normalizeHex(values["foreground"])
        else { return nil }

        let fallbackPalette = ThemeDraft.droidDefaults.colors.palette
        let resolvedPalette = zip(palette, fallbackPalette).map { normalizeHex($0.0) ?? $0.1 }
        let colors = ThemeColorSet(
            background: background,
            foreground: foreground,
            cursorColor: normalizeHex(values["cursor-color"]) ?? resolvedPalette[3],
            cursorText: normalizeHex(values["cursor-text"]) ?? background,
            selectionBackground: normalizeHex(values["selection-background"]) ?? resolvedPalette[4],
            selectionForeground: normalizeHex(values["selection-foreground"]) ?? foreground,
            palette: resolvedPalette
        )
        let draft = ThemeDraft(
            name: (parsedName?.isEmpty == false ? parsedName! : identifier),
            slug: slugify(parsedSlug?.isEmpty == false ? parsedSlug! : identifier),
            colors: colors
        )

        return ThemePreview(
            identifier: identifier,
            name: draft.name,
            source: source,
            draft: draft,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func buildContent(from draft: ThemeDraft) -> String? {
        guard let normalized = normalizedDraft(draft) else { return nil }
        var lines = [
            "\(namePrefix) \(normalized.name)",
            "\(slugPrefix) \(normalized.slug)",
            "",
        ]
        lines.append(contentsOf: normalized.colors.palette.enumerated().map { "palette = \($0.offset)=\($0.element)" })
        lines.append(contentsOf: [
            "background = \(normalized.colors.background)",
            "foreground = \(normalized.colors.foreground)",
            "cursor-color = \(normalized.colors.cursorColor)",
            "cursor-text = \(normalized.colors.cursorText)",
            "selection-background = \(normalized.colors.selectionBackground)",
            "selection-foreground = \(normalized.colors.selectionForeground)",
        ])
        return lines.joined(separator: "\n")
    }

    static func normalizedDraft(_ draft: ThemeDraft) -> ThemeDraft? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = slugify(draft.slug)
        guard !name.isEmpty, !slug.isEmpty else { return nil }
        let colors = draft.colors
        guard let background = normalizeHex(colors.background),
              let foreground = normalizeHex(colors.foreground),
              let cursorColor = normalizeHex(colors.cursorColor),
              let cursorText = normalizeHex(colors.cursorText),
              let selectionBackground = normalizeHex(colors.selectionBackground),
              let selectionForeground = normalizeHex(colors.selectionForeground)
        else { return nil }
        let palette = colors.palette.compactMap(normalizeHex)
        guard palette.count == 16 else { return nil }
        return ThemeDraft(
            name: name,
            slug: slug,
            colors: ThemeColorSet(
                background: background,
                foreground: foreground,
                cursorColor: cursorColor,
                cursorText: cursorText,
                selectionBackground: selectionBackground,
                selectionForeground: selectionForeground,
                palette: palette
            )
        )
    }

    static func normalizeHex(_ value: String?) -> String? {
        guard var trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }
        guard trimmed.count == 6, UInt32(trimmed, radix: 16) != nil else { return nil }
        return "#\(trimmed.uppercased())"
    }

    static func slugify(_ value: String) -> String {
        let lowered = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let replaced = String(lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return replaced
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    static func uniqueSlug(_ base: String, existing: Set<String>) -> String {
        let normalized = slugify(base)
        guard !normalized.isEmpty else { return UUID().uuidString.lowercased() }
        guard existing.contains(normalized) else { return normalized }
        var index = 2
        while existing.contains("\(normalized)-\(index)") {
            index += 1
        }
        return "\(normalized)-\(index)"
    }

    private static func parseValue(_ line: String, into values: inout [String: String]) {
        guard let eqIndex = line.firstIndex(of: "=") else { return }
        let key = line[..<eqIndex].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !value.isEmpty else { return }
        values[key] = value
    }

    private static func parsePalette(_ line: String, into palette: inout [String?]) {
        guard let eqIndex = line.firstIndex(of: "=") else { return }
        let value = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
        guard let splitIndex = value.firstIndex(of: "="),
              let index = Int(value[..<splitIndex]),
              index >= 0,
              index < palette.count
        else { return }
        palette[index] = String(value[value.index(after: splitIndex)...]).trimmingCharacters(in: .whitespaces)
    }
}
