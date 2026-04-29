enum DroidPopoverPresentationPolicy {
    static func shouldPreparePopover(isPresented: Bool, isShown: Bool) -> Bool {
        isPresented || isShown
    }
}
