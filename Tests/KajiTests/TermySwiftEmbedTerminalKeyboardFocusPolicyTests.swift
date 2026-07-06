import XCTest
@testable import TermySwiftEmbed

final class TerminalKeyboardFocusPolicyTests: XCTestCase {
    func testRenderUpdateDoesNotRequestFirstResponder() {
        XCTAssertFalse(TerminalKeyboardFocusPolicy.allowsFirstResponderRequest(
            isInputEnabled: true,
            trigger: .renderUpdate
        ))
    }

    func testWindowAttachmentDoesNotRequestFirstResponder() {
        XCTAssertFalse(TerminalKeyboardFocusPolicy.allowsFirstResponderRequest(
            isInputEnabled: true,
            trigger: .windowAttachment
        ))
    }

    func testExplicitHostRequestCanRequestFirstResponder() {
        XCTAssertTrue(TerminalKeyboardFocusPolicy.allowsFirstResponderRequest(
            isInputEnabled: true,
            trigger: .explicitHostRequest
        ))
    }

    func testPointerInputCanRequestFirstResponder() {
        XCTAssertTrue(TerminalKeyboardFocusPolicy.allowsFirstResponderRequest(
            isInputEnabled: true,
            trigger: .pointerInput
        ))
    }

    func testDropInputCanRequestFirstResponder() {
        XCTAssertTrue(TerminalKeyboardFocusPolicy.allowsFirstResponderRequest(
            isInputEnabled: true,
            trigger: .dropInput
        ))
    }

    func testDisabledInputNeverRequestsFirstResponder() {
        for trigger in [
            TerminalKeyboardFocusTrigger.renderUpdate,
            .windowAttachment,
            .explicitHostRequest,
            .pointerInput,
            .dropInput,
        ] {
            XCTAssertFalse(TerminalKeyboardFocusPolicy.allowsFirstResponderRequest(
                isInputEnabled: false,
                trigger: trigger
            ))
        }
    }
}
