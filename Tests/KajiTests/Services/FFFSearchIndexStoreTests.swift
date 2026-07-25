import Foundation
import FFFWorkerProtocol
import Testing

@testable import Kaji

@Suite("FFF search index store", .serialized)
struct FFFSearchIndexStoreTests {
    @Test("removing inactive paths does not start the worker")
    func inactiveRemovalDoesNotStartWorker() async {
        let launches = FFFWorkerLaunchRecorder()
        let client = FFFWorkerClient(
            workerURL: {
                launches.record()
                throw FFFSearchError.workerUnavailable
            },
            libraryURL: { URL(fileURLWithPath: "/tmp/not-used") },
            sleep: { _ in }
        )
        let store = FFFSearchIndexStore(client: client)

        await store.remove(projectPaths: ["/tmp/repo", "/tmp/repo"])

        #expect(launches.count == 0)
    }
}

private final class FFFWorkerLaunchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func record() {
        lock.withLock { value += 1 }
    }
}
