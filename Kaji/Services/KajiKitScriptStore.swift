import Foundation

@MainActor
@Observable
final class KajiKitScriptStore {
    static let shared = KajiKitScriptStore()

    private(set) var scripts: [KajiKitScript] = []
    private let scriptsFile: URL

    init(scriptsFile: URL = KajiKitDirectory.scriptsFile) {
        self.scriptsFile = scriptsFile
        load()
    }

    func visibleScripts(projectID: UUID?) -> [KajiKitScript] {
        let scoped = scripts.filter { script in
            script.scope == .global || script.projectID == projectID
        }
        var bySlug: [String: KajiKitScript] = [:]
        for script in scoped.sorted(by: { $0.scope == .global && $1.scope == .project }) {
            bySlug[script.slug] = script
        }
        return bySlug.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func resolve(slug: String, projectID: UUID?) -> KajiKitScript? {
        let normalized = Self.normalizedSlug(slug)
        return scripts.first { $0.projectID == projectID && $0.slug == normalized }
            ?? scripts.first { $0.scope == .global && $0.slug == normalized }
    }

    func save(_ draft: KajiKitScriptDraft, projectID: UUID?) {
        let now = Date()
        let scope = draft.scope
        let scopedProjectID = scope == .project ? projectID : nil
        let slug = Self.normalizedSlug(draft.slug.isEmpty ? draft.title : draft.slug)
        let command = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty, !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !command.isEmpty else { return }

        if let id = draft.id, let index = scripts.firstIndex(where: { $0.id == id }) {
            scripts[index].title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            scripts[index].slug = slug
            scripts[index].scope = scope
            scripts[index].projectID = scopedProjectID
            scripts[index].kind = draft.kind
            scripts[index].command = command
            scripts[index].directoryMode = draft.directoryMode
            scripts[index].confirmation = draft.confirmation
            scripts[index].autoCloseOnSuccess = draft.autoCloseOnSuccess
            scripts[index].updatedAt = now
        } else {
            scripts.append(KajiKitScript(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                slug: slug,
                scope: scope,
                projectID: scopedProjectID,
                kind: draft.kind,
                command: command,
                directoryMode: draft.directoryMode,
                confirmation: draft.confirmation,
                autoCloseOnSuccess: draft.autoCloseOnSuccess,
                createdAt: now,
                updatedAt: now
            ))
        }
        persist()
    }

    func delete(_ script: KajiKitScript) {
        scripts.removeAll { $0.id == script.id }
        persist()
    }

    func load() {
        do {
            try FileManager.default.createDirectory(at: scriptsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: scriptsFile.path) else { return }
            let data = try Data(contentsOf: scriptsFile)
            scripts = try JSONDecoder.kajiKit.decode([KajiKitScript].self, from: data)
        } catch {
            scripts = []
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: scriptsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.kajiKit.encode(scripts)
            try data.write(to: scriptsFile, options: .atomic)
        } catch {}
    }

    static func normalizedSlug(_ raw: String) -> String {
        raw.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
    }
}

struct KajiKitScriptDraft: Hashable {
    var id: UUID?
    var title = ""
    var slug = ""
    var scope = KajiKitScriptScope.global
    var kind = KajiKitScriptKind.command
    var command = ""
    var directoryMode = KajiKitScriptDirectoryMode.activeWorktree
    var confirmation = KajiKitScriptConfirmation.risky
    var autoCloseOnSuccess = true

    init() {}

    init(script: KajiKitScript) {
        id = script.id
        title = script.title
        slug = script.slug
        scope = script.scope
        kind = script.kind
        command = script.command
        directoryMode = script.directoryMode
        confirmation = script.confirmation
        autoCloseOnSuccess = script.autoCloseOnSuccess
    }
}

private extension JSONEncoder {
    static var kajiKit: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var kajiKit: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
