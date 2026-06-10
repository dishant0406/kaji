import SwiftUI

struct KajiAgentToolOutputView: View {
    let output: String
    let toolName: String

    var body: some View {
        KajiAgentCodeBlockView(code: output, language: language)
    }

    private var language: String? {
        switch toolName {
        case "bash": "shell"
        case "read": nil
        default:
            output.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") ? "json" : nil
        }
    }
}
