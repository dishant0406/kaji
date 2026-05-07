import Testing

@testable import Droid

struct DroidCodeGraphGitSnapshotTests {
    @Test
    func ignoresGeneratedGraphifyArtifactsWhenCheckingDirtyStatus() {
        let status = """
        ?? graphify-out/.graphify_chunk_14.json
        ?? graphify-out/GRAPH_REPORT.md
        """

        #expect(!DroidCodeGraphGitSnapshot.hasSourceChanges(status))
    }

    @Test
    func treatsSourceChangesAsDirtyBesideGeneratedArtifacts() {
        let status = """
        ?? graphify-out/.graphify_chunk_14.json
         M src/app.ts
        """

        #expect(DroidCodeGraphGitSnapshot.hasSourceChanges(status))
    }
}
