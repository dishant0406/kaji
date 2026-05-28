import Foundation
import Testing

@testable import Kaji

struct ProcessPipeCollectorTests {
    @Test
    func collectsDataBeforeProcessExit() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/printf")
        process.arguments = ["hello"]

        let pipe = Pipe()
        process.standardOutput = pipe
        let collector = ProcessPipeCollector(pipe: pipe)

        try process.run()
        process.waitUntilExit()
        collector.stop()

        #expect(String(data: collector.data, encoding: .utf8) == "hello")
    }
}
