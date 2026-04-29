import Testing

@testable import Droid

struct DroidPopoverPresentationPolicyTests {
    @Test
    func skipsPreparationWhenPopoverIsHidden() {
        #expect(!DroidPopoverPresentationPolicy.shouldPreparePopover(isPresented: false, isShown: false))
    }

    @Test
    func preparesPopoverWhenPresented() {
        #expect(DroidPopoverPresentationPolicy.shouldPreparePopover(isPresented: true, isShown: false))
    }

    @Test
    func preparesPopoverWhenAlreadyShown() {
        #expect(DroidPopoverPresentationPolicy.shouldPreparePopover(isPresented: false, isShown: true))
    }
}
