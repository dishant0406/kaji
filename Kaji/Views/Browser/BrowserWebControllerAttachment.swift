struct BrowserWebControllerAttachment {
    let surface: NativeBrowserSurfaceView
    let page: BrowserPageState
    let projectPath: String
    let isActive: Bool
    let deviceProfile: BrowserDeviceProfile
    let callbacks: BrowserSurfaceCallbacks
}
