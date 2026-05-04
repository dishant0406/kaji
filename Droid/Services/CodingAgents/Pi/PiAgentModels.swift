import Foundation

enum PiAgentModels {
    static func options() -> [String] {
        CodingAgentCommandRunner.lines(executableName: "pi", arguments: ["--offline", "--list-models"])
            .dropFirst()
            .compactMap(modelID(from:))
    }

    static func modelID(from line: String) -> String? {
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 2 else { return nil }
        guard fields[0] != "provider" else { return nil }
        return "\(fields[0])/\(fields[1])"
    }
}
