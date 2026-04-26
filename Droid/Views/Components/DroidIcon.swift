import SwiftUI

struct DroidIcon: View {
    let systemName: String
    var size: CGFloat = 12

    var body: some View {
        if let glyph = HugeIconCatalog.glyph(for: systemName) {
            Text(glyph)
                .font(HugeIconFont.font(size: size))
                .lineLimit(1)
        } else {
            Image(systemName: systemName)
                .font(.system(size: size))
        }
    }
}
