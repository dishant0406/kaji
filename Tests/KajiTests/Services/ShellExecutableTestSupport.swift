import Foundation

struct ShellExecutableFixture {
    let fileManager = FileManager.default
    let root: URL
    let home: URL
    let shell: URL
    let firstBin: URL
    let secondBin: URL
    let interactiveBin: URL

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        shell = root.appendingPathComponent("shell")
        firstBin = root.appendingPathComponent("first-bin", isDirectory: true)
        secondBin = root.appendingPathComponent("second-bin", isDirectory: true)
        interactiveBin = root.appendingPathComponent("interactive-bin", isDirectory: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: firstBin, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: secondBin, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: interactiveBin, withIntermediateDirectories: true)
        try writeShell()
    }

    func env(path directories: [URL]? = nil) -> [String: String] {
        [
            "SHELL": shell.path,
            "PATH": (directories ?? [firstBin]).map(\.path).joined(separator: ":"),
        ]
    }

    func writeExecutable(_ name: String, in directory: URL? = nil) throws -> URL {
        let url = (directory ?? firstBin).appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func cleanup() {
        try? fileManager.removeItem(at: root)
    }

    private func writeShell() throws {
        try Data("""
        #!/bin/sh
        whence() {
          name=""
          for arg in "$@"; do
            name="$arg"
          done
          old_ifs="$IFS"
          IFS=:
          for dir in $PATH; do
            if [ -x "$dir/$name" ]; then
              printf '%s\\n' "$dir/$name"
            fi
          done
          IFS="$old_ifs"
        }
        if [ "$1" = "-lc" ]; then
          eval "$2"
        elif [ "$1" = "-i" ] && [ "$2" = "-c" ]; then
          PATH="${KAJI_TEST_INTERACTIVE_PATH:-$PATH}"
          eval "$3"
        else
          eval "$1"
        fi
        """.utf8).write(to: shell)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
    }
}
