import Foundation
import Testing

@testable import Kaji

@Suite("FFF dynamic library")
struct FFFDynamicLibraryTests {
    @Test("missing library throws instead of trapping")
    func missingLibraryThrows() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = directory.appendingPathComponent("missing.dylib")

        #expect(throws: FFFSearchError.self) {
            try FFFDynamicLibrary.load(libraryURL: libraryURL)
        }
    }
}
