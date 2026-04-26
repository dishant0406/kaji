import AppKit
import SwiftUI

struct DiffSectionDivider: View {
    let text: String
    var showsTopBorder: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .droidFont(size: 11, design: .monospaced)
                .foregroundStyle(DroidTheme.fgDim)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 10)
            Spacer(minLength: 8)
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(DroidTheme.bg)
        .overlay(alignment: .top) {
            if showsTopBorder {
                Rectangle().fill(DroidTheme.border).frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(DroidTheme.border).frame(height: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Diff section: \(text)")
    }
}

func hunkLabel(_ raw: String) -> String {
    guard raw.count > 2,
          let closingRange = raw.range(of: "@@", range: raw.index(raw.startIndex, offsetBy: 2) ..< raw.endIndex)
    else { return raw }
    let after = raw[closingRange.upperBound...].trimmingCharacters(in: .whitespaces)
    return after.isEmpty ? raw : after
}

func lineNumberWidth(for maxLineNumber: Int) -> CGFloat {
    let digitCount = max(String(maxLineNumber).count, 1)
    return CGFloat(digitCount) * 8 + 12
}

func maxLineNumber(in rows: [DiffDisplayRow]) -> Int {
    rows.reduce(0) { result, row in
        max(result, row.oldLineNumber ?? 0, row.newLineNumber ?? 0)
    }
}

enum DiffBackgroundSide {
    case left
    case right
    case both
}

struct DiffHighlightRule: @unchecked Sendable {
    let regex: NSRegularExpression
    let color: NSColor
}

struct DiffRenderTheme: @unchecked Sendable {
    let rules: [DiffHighlightRule]
    let additionColor: NSColor
    let deletionColor: NSColor
    let defaultColor: NSColor
    let additionBackground: NSColor
    let deletionBackground: NSColor
    let hunkBackground: NSColor
    let collapsedBackground: NSColor
    let font: NSFont

    @MainActor
    static func current() -> DiffRenderTheme {
        DiffRenderTheme(
            rules: Self.buildRules(),
            additionColor: DroidTheme.nsDiffAdd,
            deletionColor: DroidTheme.nsDiffRemove,
            defaultColor: GhosttyService.shared.foregroundColor,
            additionBackground: DroidTheme.nsDiffAdd.withAlphaComponent(0.16),
            deletionBackground: DroidTheme.nsDiffRemove.withAlphaComponent(0.16),
            hunkBackground: DroidTheme.nsDiffHunk.withAlphaComponent(0.1),
            collapsedBackground: DroidTheme.nsBg,
            font: DiffMetrics.font
        )
    }

    private struct RuleDefinition {
        let pattern: String
        let color: NSColor
        let options: NSRegularExpression.Options
    }

    @MainActor
    private static func buildRules() -> [DiffHighlightRule] {
        let definitions: [RuleDefinition] = [
            RuleDefinition(pattern: #"'(?:\\.|[^'\\])*'"#, color: DroidTheme.nsDiffString, options: []),
            RuleDefinition(pattern: #""(?:\\.|[^"\\])*""#, color: DroidTheme.nsDiffString, options: []),
            RuleDefinition(pattern: #"`(?:\\.|[^`\\])*`"#, color: DroidTheme.nsDiffString, options: []),
            RuleDefinition(pattern: #"\b\d+(?:\.\d+)?\b"#, color: DroidTheme.nsDiffNumber, options: []),
            RuleDefinition(pattern: #"//.*$"#, color: DroidTheme.nsDiffComment, options: [.anchorsMatchLines]),
        ]

        var result: [DiffHighlightRule] = []
        for definition in definitions {
            guard let regex = try? NSRegularExpression(pattern: definition.pattern, options: definition.options)
            else { continue }
            result.append(DiffHighlightRule(regex: regex, color: definition.color))
        }
        return result
    }
}
