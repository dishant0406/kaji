import Darwin
import Foundation

enum DebugFileLog {
    private static let storage = DebugFileLogStorage()

    static var fileURL: URL {
        KajiFileStorage.fileURL(filename: "kaji-debug.log")
    }

    static func start() {
        let result = storage.start(fileURL: fileURL)
        if result.shouldInstallHandlers {
            installCrashHandlers()
        }
        if result.didOpen {
            log("Lifecycle", "debug log started path=\(fileURL.path)")
        }
    }

    static func log(_ category: String, _ message: @autoclosure () -> String) {
        guard shouldLog(category) else { return }
        startIfNeeded()
        let timestamp = Self.timestamp()
        let thread = Thread.isMainThread ? "main" : "background"
        writeLine("\(timestamp) [\(thread)] [\(category)] \(message())")
    }

    static func logError(_ category: String, _ error: Error, context: @autoclosure () -> String) {
        log(category, "\(context()) error=\(error.localizedDescription)")
    }

    private static func startIfNeeded() {
        if storage.isOpen { return }
        start()
    }

    private static func writeLine(_ line: String) {
        storage.writeLine(line)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func shouldLog(_ category: String) -> Bool {
        if ProcessInfo.processInfo.environment["KAJI_EDITOR_DEBUG_LOGS"] == "1" { return true }
        return ![
            "EditorDraw",
            "EditorViewport",
            "EditorSyntax",
            "EditorDecorations",
        ].contains(category)
    }

    private static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "nil"
            let callStack = exception.callStackSymbols.joined(separator: " | ")
            DebugFileLog.log(
                "Crash",
                "uncaught exception name=\(exception.name.rawValue) reason=\(reason) callStack=\(callStack)"
            )
        }
        signal(SIGABRT, signalHandler)
        signal(SIGILL, signalHandler)
        signal(SIGSEGV, signalHandler)
        signal(SIGFPE, signalHandler)
        signal(SIGBUS, signalHandler)
        signal(SIGPIPE, signalHandler)
    }

    private static let signalHandler: @convention(c) (Int32) -> Void = { signal in
        let message = "\n[Crash] received signal=\(signal)\n"
        storage.writeRaw(message)
        Darwin.signal(signal, SIG_DFL)
        Darwin.raise(signal)
    }
}

private final class DebugFileLogStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var didInstallCrashHandlers = false

    var isOpen: Bool {
        lock.lock()
        let value = descriptor != -1
        lock.unlock()
        return value
    }

    func start(fileURL: URL) -> (didOpen: Bool, shouldInstallHandlers: Bool) {
        lock.lock()
        let didOpen = descriptor == -1
        if didOpen {
            let path = fileURL.path
            descriptor = path.withCString { pointer in
                open(pointer, O_CREAT | O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR)
            }
        }
        let shouldInstallHandlers = !didInstallCrashHandlers
        didInstallCrashHandlers = true
        lock.unlock()
        return (didOpen, shouldInstallHandlers)
    }

    func writeLine(_ line: String) {
        writeRaw(line + "\n")
    }

    func writeRaw(_ output: String) {
        lock.lock()
        let current = descriptor
        if current != -1 {
            output.withCString { pointer in
                _ = Darwin.write(current, pointer, strlen(pointer))
            }
        }
        lock.unlock()
    }
}
