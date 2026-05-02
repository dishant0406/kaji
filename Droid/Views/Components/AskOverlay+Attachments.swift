import SwiftUI

extension AskOverlay {
    func removeAttachment(_ attachment: AskAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    func pasteAttachments() -> Bool {
        let pasted = AskAttachmentLoader.attachments()
        guard !pasted.isEmpty else { return false }
        attachments.append(contentsOf: pasted)
        return true
    }
}
