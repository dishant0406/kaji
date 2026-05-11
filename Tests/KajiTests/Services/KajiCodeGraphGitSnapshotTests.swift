import Testing

@testable import Kaji

struct KajiCodeGraphGitSnapshotTests {
    @Test
    func ignoresGeneratedGraphifyArtifactsWhenCheckingDirtyStatus() {
        let status = """
        ?? graphify-out/.graphify_chunk_14.json
        ?? graphify-out/GRAPH_REPORT.md
        """

        #expect(!KajiCodeGraphGitSnapshot.hasSourceChanges(status))
    }

    @Test
    func treatsSourceChangesAsDirtyBesideGeneratedArtifacts() {
        let status = """
        ?? graphify-out/.graphify_chunk_14.json
         M src/app.ts
        """

        #expect(KajiCodeGraphGitSnapshot.hasSourceChanges(status))
    }
}
