import Testing

@testable import Kaji

@Suite("Mermaid code block normalization")
struct MermaidCodeBlockNormalizerTests {
    @Test("normalizeLabelNewlines converts real newlines inside bracket labels")
    func normalizeLabelNewlinesConvertsRealNewlinesInsideLabels() {
        let unixInput = "graph TD\nA[Chargeback DB\n(Kafka/Flink write)] --> B\n"
        let unixOutput = MermaidCodeBlockNormalizer.normalizeLabelNewlines(in: unixInput)
        #expect(unixOutput == "graph TD\nA[Chargeback DB<br/>(Kafka/Flink write)] --> B\n")

        let windowsInput = "graph TD\r\nA[Chargeback DB\r\n(Kafka/Flink write)] --> B\r\n"
        let windowsOutput = MermaidCodeBlockNormalizer.normalizeLabelNewlines(in: windowsInput)
        #expect(windowsOutput == "graph TD\r\nA[Chargeback DB<br/>(Kafka/Flink write)] --> B\r\n")
    }

    @Test("normalizeLabelNewlines preserves newlines outside bracket labels")
    func normalizeLabelNewlinesPreservesOutsideLabelNewlines() {
        let input = "graph TD\nA[Label] --> B\nB --> C\n"
        let output = MermaidCodeBlockNormalizer.normalizeLabelNewlines(in: input)

        #expect(output == input)
    }

    @Test("normalizeLabelNewlines converts literal \\n only inside bracket labels")
    func normalizeLabelNewlinesConvertsOnlyInLabels() {
        let input = "graph TD\nA[Line1\\nLine2] --> B\nB --> C\\nD\n"
        let output = MermaidCodeBlockNormalizer.normalizeLabelNewlines(in: input)

        #expect(output == "graph TD\nA[Line1<br/>Line2] --> B\nB --> C\\nD\n")
    }

    @Test("normalizeLabelNewlines handles nested bracket text conservatively")
    func normalizeLabelNewlinesNestedBrackets() {
        let input = "flowchart LR\nA[Outer [Inner\\nLabel] text\\nmore] --> B\n"
        let output = MermaidCodeBlockNormalizer.normalizeLabelNewlines(in: input)

        #expect(output == "flowchart LR\nA[Outer [Inner<br/>Label] text<br/>more] --> B\n")
    }

    @Test("normalizeMermaidCodeBlocks only rewrites mermaid fenced blocks")
    func normalizeMermaidCodeBlocksScope() {
        let markdown = """
        Before

        ```swift
        let text = "[A\\nB]"
        ```

        ```mermaid
        graph TD
        A[Hello\\nWorld] --> B
        B --> C\\nD
        ```

        After
        """

        let output = MermaidCodeBlockNormalizer.normalizeMermaidCodeBlocks(in: markdown)

        #expect(output.contains("let text = \"[A\\nB]\""))
        #expect(output.contains("A[Hello<br/>World] --> B"))
        #expect(output.contains("B --> C\\nD"))
    }
}
