import Foundation
import Testing

@testable import Droid

struct AskHistoryCatalogTests {
    @Test
    func codexHistorySkipsCorruptFilesAndPrioritizesCurrentProject() throws {
        let root = try temporaryDirectory()
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome.appendingPathComponent("sessions/2026/05/01", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try codexFile(
            id: "old-session",
            cwd: "/tmp/other",
            title: "Other work",
            url: sessions.appendingPathComponent("old.jsonl")
        )
        try codexFile(
            id: "current-session",
            cwd: "/tmp/muxy",
            title: "Fix muxy",
            url: sessions.appendingPathComponent("current.jsonl")
        )
        try "not json".write(to: sessions.appendingPathComponent("bad.jsonl"), atomically: true, encoding: .utf8)

        let options = AskHistoryCatalog.options(
            provider: .codex,
            projectPath: "/tmp/muxy",
            query: "",
            env: ["CODEX_HOME": codexHome.path, "HOME": root.path]
        )

        #expect(options.first?.sessionID == "current-session")
        #expect(options.map(\.sessionID).contains("old-session"))
        #expect(!options.map(\.sessionID).contains("bad"))
    }

    @Test
    func codexHistoryReadsOnlyBoundedFilePrefix() throws {
        let root = try temporaryDirectory()
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome.appendingPathComponent("sessions/2026/05/01", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let url = sessions.appendingPathComponent("large.jsonl")
        try codexFile(id: "large-session", cwd: "/tmp/muxy", title: "Large transcript", url: url)
        let largeTail = String(repeating: "x", count: 1024 * 1024)
        let hidden = #"{"type":"session_meta","payload":{"id":"hidden-session","cwd":"/tmp/other"}}"#
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\(largeTail)\n\(hidden)\n".utf8))
        try handle.close()

        let options = AskHistoryCatalog.options(
            provider: .codex,
            projectPath: "/tmp/muxy",
            query: "",
            env: ["CODEX_HOME": codexHome.path, "HOME": root.path]
        )

        #expect(options.map(\.sessionID) == ["large-session"])
    }

    @Test
    func skillCatalogPrefersProjectSkillNames() throws {
        let root = try temporaryDirectory()
        let project = root.appendingPathComponent("project", isDirectory: true)
        let projectSkill = project.appendingPathComponent(".agents/skills/copywriting", isDirectory: true)
        let globalSkill = root.appendingPathComponent(".agents/skills/copywriting", isDirectory: true)
        try FileManager.default.createDirectory(at: projectSkill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: globalSkill, withIntermediateDirectories: true)
        try "# Project Copywriting".write(to: projectSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "# Global Copywriting".write(to: globalSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let options = AskSkillCatalog.options(
            provider: .codex,
            projectPath: project.path,
            query: "copy",
            env: ["HOME": root.path]
        )

        #expect(options.count == 1)
        #expect(options.first?.title == "Project Copywriting")
    }

    @Test
    func skillCatalogReturnsNoOptionsForTerminal() throws {
        let root = try temporaryDirectory()
        let skills = root.appendingPathComponent(".agents/skills/copywriting", isDirectory: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try "# Copywriting".write(to: skills.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let options = AskSkillCatalog.options(
            provider: .terminal,
            projectPath: nil,
            query: "copy",
            env: ["HOME": root.path]
        )

        #expect(options.isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func codexFile(id: String, cwd: String, title: String, url: URL) throws {
        let meta = #"{"type":"session_meta","payload":{"id":"\#(id)","cwd":"\#(cwd)"}}"#
        let user = #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"\#(title)"}]}}"#
        try "\(meta)\n\(user)\n".write(to: url, atomically: true, encoding: .utf8)
    }
}
