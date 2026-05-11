enum KajiPopoverPresentationPolicy {
    static func shouldPreparePopover(isPresented: Bool, isShown: Bool) -> Bool {
        isPresented || isShown
    }
}
