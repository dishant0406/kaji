import SwiftUI

struct BrowserDeviceSelect: View {
    @Binding var selection: String

    var body: some View {
        KajiSelect(
            options: BrowserDeviceProfiles.all.map { profile in
                KajiSelectOption(id: profile.id, title: "\(profile.title) - \(profile.family.rawValue)", value: profile.id)
            },
            selection: $selection,
            width: 176,
            variant: .plain
        )
    }
}
