import SwiftUI

struct KajiAgentTaskToolView: View {
    let details: KajiAgentTaskToolDetails

    var body: some View {
        KajiAgentSubagentListView(layout: KajiAgentSubagentInlineLayout(details: details))
    }
}
