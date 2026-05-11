import Testing

@testable import Kaji

struct KajiPopoverPresentationPolicyTests {
    @Test
    func skipsPreparationWhenPopoverIsHidden() {
        #expect(!KajiPopoverPresentationPolicy.shouldPreparePopover(isPresented: false, isShown: false))
    }

    @Test
    func preparesPopoverWhenPresented() {
        #expect(KajiPopoverPresentationPolicy.shouldPreparePopover(isPresented: true, isShown: false))
    }

    @Test
    func preparesPopoverWhenAlreadyShown() {
        #expect(KajiPopoverPresentationPolicy.shouldPreparePopover(isPresented: false, isShown: true))
    }
}
