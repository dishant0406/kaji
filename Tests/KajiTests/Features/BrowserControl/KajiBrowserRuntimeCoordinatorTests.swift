import Testing

@testable import Kaji

@MainActor
@Suite("KajiBrowserRuntimeCoordinator paths")
struct KajiBrowserRuntimeCoordinatorTests {
    @Test("root cache follows explicit profile override")
    func rootCacheFollowsExplicitProfileOverride() {
        let environment = ["KAJI_CEF_PROFILE_PATH": "/tmp/kaji-cef-profile"]

        #expect(KajiBrowserRuntimeCoordinator.profilePath(environment: environment) == "/tmp/kaji-cef-profile")
        #expect(KajiBrowserRuntimeCoordinator.rootCachePath(environment: environment) == "/tmp/kaji-cef-profile")
    }
}
