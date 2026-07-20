import Foundation

@main
struct KajiHookClient {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else { return }
        args.removeFirst()

        switch command {
        case "send":
            send(args)
        case "ask-complete":
            askComplete(args)
        case "claude-hook":
            ClaudeHookHandler.handle(event: args.first ?? "", input: stdin())
        case "codex-activity":
            CodexHookHandler.handle(args: args, input: stdin())
        case "kajicode-hook":
            KajiCodeHookHandler.handle(event: args.first ?? "", input: stdin())
        default:
            return
        }
    }

    private static func send(_ args: [String]) {
        guard args.count >= 3 else { return }
        HookEventEmitter.emit(
            type: args[0],
            paneID: args[1].isEmpty ? nil : args[1],
            title: args[2],
            body: args.count > 3 ? HookTextSanitizer.clean(args[3], limit: args[0].hasSuffix("_session") ? 2000 : 500) : ""
        )
    }

    private static func askComplete(_ args: [String]) {
        guard args.count >= 3 else { return }
        let paneID = ProcessInfo.processInfo.environment["KAJI_PANE_ID"]
        guard let paneID, !paneID.isEmpty else { return }
        HookEventEmitter.emit(
            type: args[0],
            paneID: paneID,
            title: args[1],
            body: HookTextSanitizer.clean(args[2], limit: 200)
        )
    }

    private static func stdin() -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
