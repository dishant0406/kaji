import SwiftUI

struct MeetingTranscriptionAttestationRow: View {
    @ObservedObject var controller: MeetingTranscriptionSettingsController

    var body: some View {
        if let attestation = controller.selectedRetentionPresentation?.requiredAttestation,
           controller.requiresSelectedAttestation
        {
            SettingsDetailToggleRow(
                label: "Account-control attestation",
                detail: attestation.claim,
                isOn: Binding(
                    get: {
                        controller.settingsStore.settings.sttAccountAttestations.contains {
                            $0.kind == attestation && $0.isExact
                        }
                    },
                    set: { controller.setAttestation(attestation, enabled: $0) }
                )
            )
        }
    }
}
