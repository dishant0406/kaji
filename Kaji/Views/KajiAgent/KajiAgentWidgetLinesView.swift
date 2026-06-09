import SwiftUI

struct KajiAgentWidgetLinesView: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(KajiTheme.fgDim)
            }
        }
        .padding(12)
        .frame(maxWidth: 760, alignment: .leading)
        .background(KajiTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}
