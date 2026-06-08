import Foundation

enum UserCommandShortcutValidator {
    static func slug(from raw: String) -> String {
        raw.lowercased().unicodeScalars.compactMap { scalar in
            guard isASCIILowercaseLetter(scalar) || isASCIIDigit(scalar) else { return nil }
            return String(scalar)
        }.joined()
    }

    static func validate(
        draft: UserCommandShortcutDraft,
        existing shortcuts: [UserCommandShortcut]
    ) -> UserCommandShortcutValidation {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSlug = draft.slug.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
        var errors: [UserCommandShortcutValidationError] = []

        if name.isEmpty {
            errors.append(.nameRequired)
        }
        if cleanSlug.isEmpty {
            errors.append(.slugRequired)
        } else if slug(from: cleanSlug) != cleanSlug {
            errors.append(.slugInvalid)
        } else if reservedSlugs.contains(cleanSlug) {
            errors.append(.slugReserved)
        } else if shortcuts.contains(where: { $0.id != draft.id && $0.slug == cleanSlug }) {
            errors.append(.slugConflict)
        }
        if command.isEmpty {
            errors.append(.commandRequired)
        } else {
            errors.append(contentsOf: UserCommandShortcutTemplateParser.parse(command).errors.map { .templateInvalid($0.message) })
        }

        return UserCommandShortcutValidation(errors: errors)
    }

    static var reservedSlugs: Set<String> {
        Set(AskAnnotationKey.allCases.map(\.rawValue))
            .union(GitPaletteCommand.allCases.map(\.rawValue))
            .union(AskSlashCommand.allCases.map(\.rawValue))
    }

    private static func isASCIILowercaseLetter(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 97 && scalar.value <= 122
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }
}
