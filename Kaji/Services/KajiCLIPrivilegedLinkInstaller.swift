import Foundation

enum KajiCLIPrivilegedLinkInstaller {
    static func install(source: URL, link: URL) -> Bool {
        run(script: [
            "/bin/mkdir -p \(quote(link.deletingLastPathComponent().path))",
            "/bin/rm -f \(quote(link.path))",
            "/bin/ln -s \(quote(source.path)) \(quote(link.path))",
        ].joined(separator: " && "))
    }

    static func remove(link: URL) -> Bool {
        run(script: "/bin/rm -f \(quote(link.path))")
    }

    private static func run(script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \(appleScriptString(script)) with administrator privileges"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
