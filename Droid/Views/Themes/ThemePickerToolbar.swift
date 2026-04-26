import SwiftUI

struct ThemePickerToolbar: View {
    @Binding var query: String
    let onImport: () -> Void
    let onCreate: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            DroidInput(
                placeholder: "Search themes",
                text: $query,
                leadingIcon: "magnifyingglass"
            )
            Button("Import", action: onImport)
                .buttonStyle(DroidButtonStyle(.secondary, size: .small))
            Button(action: onCreate) {
                DroidIcon(systemName: "plus", size: 12)
            }
            .buttonStyle(DroidButtonStyle(.secondary, size: .small))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
