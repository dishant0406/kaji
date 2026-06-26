import SwiftUI

struct CreatePRGitHubAccountField: View {
    let isLoading: Bool
    let accounts: [GitHubAccount]
    @Binding var selection: String

    var body: some View {
        if isLoading {
            HStack(spacing: 8) {
                KajiSpinner(size: 12, lineWidth: 1.4, color: KajiTheme.fgMuted)
                Text("Loading GitHub accounts")
                    .kajiFont(size: 11)
                    .foregroundStyle(KajiTheme.fgDim)
            }
        } else if accounts.count > 1 {
            KajiLabeledField("GitHub account") {
                KajiSelect(
                    options: options,
                    selection: $selection,
                    placeholder: "Select account"
                )
            }
        }
    }

    private var options: [KajiSelectOption<String>] {
        accounts.map { KajiSelectOption(id: $0.id, title: $0.menuTitle, value: $0.id) }
    }
}
