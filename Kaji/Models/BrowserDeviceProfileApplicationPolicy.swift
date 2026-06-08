enum BrowserDeviceProfileApplicationPolicy {
    static func shouldApply(current: BrowserDeviceProfile?, next: BrowserDeviceProfile) -> Bool {
        current != next
    }
}
