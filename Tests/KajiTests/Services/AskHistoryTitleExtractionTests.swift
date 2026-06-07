import Foundation
import Testing

@testable import Kaji

struct AskHistoryTitleExtractionTests {
    @Test
    func codexHistorySkipsInjectedInstructionMessages() throws {
        let root = try temporaryDirectory()
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome.appendingPathComponent("sessions/2026/05/08", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let url = sessions.appendingPathComponent("session.jsonl")
        let lines = [
            codexMeta(id: "codex-session", cwd: "/tmp/muxy"),
            codexUserText("# AGENTS.md instructions for /tmp/muxy\n\n<INSTRUCTIONS>Use Swift.</INSTRUCTIONS>"),
            codexUserText("<environment_context>\n  <cwd>/tmp/muxy</cwd>\n</environment_context>"),
            codexUserText("fix history titles"),
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)

        let options = AskHistoryCatalog.options(
            provider: .codex,
            projectPath: "/tmp/muxy",
            query: "",
            env: ["CODEX_HOME": codexHome.path, "HOME": root.path]
        )

        #expect(options.first?.title == "fix history titles")
    }

    @Test
    func opencodeDatabaseHistoryUsesPromptWhenTitleIsDefault() throws {
        let root = try temporaryDirectory()
        let database = root.appendingPathComponent("opencode.db")
        try createOpenCodeDatabase(at: database)
        try runSQLite(database, sql: """
        insert into session (id, directory, title, time_updated, time_archived)
        values ('opencode-session', '/tmp/muxy', 'New session - 2026-05-08T07:17:46.748Z', 1778224723118, null);
        insert into message (id, session_id, time_created, time_updated, data)
        values ('message-1', 'opencode-session', 1, 1, '{"role":"user"}');
        insert into part (id, message_id, session_id, time_created, time_updated, data)
        values ('part-1', 'message-1', 'opencode-session', 1, 1, '{"type":"text","text":"fix opencode history titles"}');
        """)

        let options = AskHistoryCatalog.options(
            provider: .opencode,
            projectPath: "/tmp/muxy",
            query: "",
            env: ["HOME": root.path, "OPENCODE_DB_PATH": database.path]
        )

        #expect(options.first?.title == "fix opencode history titles")
    }

    @Test
    func opencodeDatabaseHistoryScansBoundedRecentSessions() throws {
        let root = try temporaryDirectory()
        let database = root.appendingPathComponent("opencode.db")
        try createOpenCodeDatabase(at: database)
        try runSQLite(database, sql: """
        insert into session (id, directory, title, time_updated, time_archived)
        values
          ('old-session', '/tmp/muxy', 'Old work', 1, null),
          ('middle-session', '/tmp/muxy', 'Middle work', 2, null),
          ('new-session', '/tmp/muxy', 'New work', 3, null);
        """)

        let options = AskHistoryCatalog.options(
            provider: .opencode,
            projectPath: "/tmp/muxy",
            query: "",
            env: ["HOME": root.path, "OPENCODE_DB_PATH": database.path, "OPENCODE_HISTORY_SCAN_LIMIT": "2"]
        )

        #expect(options.map(\.sessionID) == ["new-session", "middle-session"])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func codexMeta(id: String, cwd: String) -> String {
        #"{"type":"session_meta","payload":{"id":"\#(id)","cwd":"\#(cwd)"}}"#
    }

    private func codexUserText(_ text: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [["type": "input_text", "text": text]])
        let content = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return #"{"type":"response_item","payload":{"type":"message","role":"user","content":\#(content)}}"#
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
        create table message (
            id text primary key,
            session_id text not null,
            time_created integer not null,
            time_updated integer not null,
            data text not null
        );
        create table part (
            id text primary key,
            message_id text not null,
            session_id text not null,
            time_created integer not null,
            time_updated integer not null,
            data text not null
        );
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
