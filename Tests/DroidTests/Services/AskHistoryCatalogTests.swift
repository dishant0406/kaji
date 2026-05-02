import Foundation
import Testing

@testable import Droid

struct AskHistoryCatalogTests {
    @Test
    func codexHistorySkipsCorruptFilesAndScopesToCurrentProject() throws {
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
        #expect(!options.map(\.sessionID).contains("old-session"))
        #expect(!options.map(\.sessionID).contains("bad"))
    }

    @Test
    func historyReturnsAllProjectsWhenProjectPathIsMissing() throws {
        let root = try temporaryDirectory()
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome.appendingPathComponent("sessions/2026/05/01", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try codexFile(id: "other-session", cwd: "/tmp/other", title: "Other work", url: sessions.appendingPathComponent("other.jsonl"))
        try codexFile(id: "current-session", cwd: "/tmp/muxy", title: "Fix muxy", url: sessions.appendingPathComponent("current.jsonl"))

        let options = AskHistoryCatalog.options(
            provider: .codex,
            projectPath: nil,
            query: "",
            env: ["CODEX_HOME": codexHome.path, "HOME": root.path]
        )

        #expect(Set(options.map(\.sessionID)) == ["current-session", "other-session"])
    }

    @Test
    func opencodeHistoryScopesToCurrentProject() throws {
        let root = try temporaryDirectory()
        let sessions = root.appendingPathComponent(".local/share/opencode/storage/session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try opencodeFile(id: "other-session", cwd: "/tmp/other", title: "Other work", url: sessions.appendingPathComponent("other.json"))
        try opencodeFile(id: "current-session", cwd: "/tmp/muxy", title: "Fix muxy", url: sessions.appendingPathComponent("current.json"))

        let options = AskHistoryCatalog.options(
            provider: .opencode,
            projectPath: "/tmp/muxy",
            query: "",
            env: ["HOME": root.path]
        )

        #expect(options.map(\.sessionID) == ["current-session"])
    }

    @Test
    func opencodeHistoryReadsCurrentDatabaseSessions() throws {
        let root = try temporaryDirectory()
        let database = root.appendingPathComponent("opencode.db")
        try createOpenCodeDatabase(at: database)
        try insertOpenCodeDatabaseSession(
            database: database,
            id: "other-session",
            directory: "/tmp/other",
            title: "Other work",
            updatedAt: 1_770_000_000_000
        )
        try insertOpenCodeDatabaseSession(
            database: database,
            id: "current-session",
            directory: "/tmp/muxy",
            title: "Fix muxy",
            updatedAt: 1_780_000_000_000
        )

        let options = AskHistoryCatalog.options(
            provider: .opencode,
            projectPath: "/tmp/muxy",
            query: "",
            env: ["HOME": root.path, "OPENCODE_DB_PATH": database.path]
        )

        #expect(options.map(\.sessionID) == ["current-session"])
    }

    @Test
    func claudeHistoryScopesToCurrentProject() throws {
        let root = try temporaryDirectory()
        let sessions = root.appendingPathComponent(".claude/projects/muxy", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try claudeFile(id: "other-session", cwd: "/tmp/other", title: "Other work", url: sessions.appendingPathComponent("other.jsonl"))
        try claudeFile(id: "current-session", cwd: "/tmp/muxy", title: "Fix muxy", url: sessions.appendingPathComponent("current.jsonl"))

        let options = AskHistoryCatalog.options(
            provider: .claude,
            projectPath: "/tmp/muxy",
            query: "",
            env: ["HOME": root.path]
        )

        #expect(options.map(\.sessionID) == ["current-session"])
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

    private func opencodeFile(id: String, cwd: String, title: String, url: URL) throws {
        let json = #"{"id":"\#(id)","directory":"\#(cwd)","title":"\#(title)","time":{"updated":1770000000000}}"#
        try json.write(to: url, atomically: true, encoding: .utf8)
    }

    private func claudeFile(id: String, cwd: String, title: String, url: URL) throws {
        let json = #"{"type":"user","sessionId":"\#(id)","cwd":"\#(cwd)","message":{"content":"\#(title)"}}"#
        try "\(json)\n".write(to: url, atomically: true, encoding: .utf8)
    }

    private func createOpenCodeDatabase(at url: URL) throws {
        try runSQLite(url, sql: """
        create table session (
            id text primary key,
            directory text not null,
            title text not null,
            time_updated integer not null,
            time_archived integer
        );
        """)
    }

    private func insertOpenCodeDatabaseSession(
        database: URL,
        id: String,
        directory: String,
        title: String,
        updatedAt: Int
    ) throws {
        try runSQLite(database, sql: """
        insert into session (id, directory, title, time_updated, time_archived)
        values ('\(id)', '\(directory)', '\(title)', \(updatedAt), null);
        """)
    }

    private func runSQLite(_ database: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, sql]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
