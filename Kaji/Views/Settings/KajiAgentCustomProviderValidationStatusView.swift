import SwiftUI

struct KajiAgentCustomProviderValidationStatusView: View {
    let result: KajiAgentCustomProviderValidation?

    var body: some View {
        if let result {
            HStack(alignment: .top, spacing: 7) {
                KajiIcon(systemName: result.ok ? "checkmark.circle" : "xmark.circle", size: 11)
                Text(result.summary)
                    .kajiFont(size: 11)
            }
            .foregroundStyle(result.ok ? KajiTheme.diffAddFg : KajiTheme.diffRemoveFg)
        }
    }
}
