import SwiftUI

struct ThemePickerToolbar: View {
    @Binding var query: String
    let onImport: () -> Void
    let onCreate: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            KajiInput(
                placeholder: "Search themes",
                text: $query,
                leadingIcon: "magnifyingglass"
            )
            Button("Import", action: onImport)
                .buttonStyle(KajiButtonStyle(.secondary, size: .small))
            Button(action: onCreate) {
                KajiIcon(systemName: "plus", size: 12)
            }
            .buttonStyle(KajiButtonStyle(.secondary, size: .small))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
