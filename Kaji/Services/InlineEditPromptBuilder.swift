import Foundation

enum InlineEditPromptBuilder {
    static func prompt(filePath: String, instruction: String, selectedCode: String, languageID: String? = nil) -> String {
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        let languageLine = languageID.map { "Language: \($0)\n\n" } ?? ""
        return """
        Rewrite the selected code from \(fileName).

        \(languageLine)Preserve surrounding behavior and formatting style. Return a drop-in replacement for the selection only.

        Instruction:
        \(instruction.trimmingCharacters(in: .whitespacesAndNewlines))

        Return only the replacement code. Do not include markdown fences, commentary, or explanations.

        Selected code:
        \(selectedCode)
        """
    }
}
