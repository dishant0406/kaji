import SwiftUI

struct KajiAgentTurnView: View {
    let turn: KajiAgentTurn
    @Binding var expandedToolGroups: Set<UUID>
    @Binding var collapsedToolGroups: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KajiAgentTurnAnchor(id: turn.id)
                .frame(height: 0)
            if let user = turn.user {
                KajiAgentMessageRow(message: user)
                    .equatable()
            }
            ForEach(turn.blocks) { block in
                switch block {
                case let .message(message):
                    KajiAgentMessageRow(message: message)
                        .equatable()
                case let .toolGroup(group):
                    KajiAgentToolGroupView(
                        group: group,
                        expandedGroups: $expandedToolGroups,
                        collapsedGroups: $collapsedToolGroups
                    )
                }
            }
        }
        .id(turn.id)
    }
}
