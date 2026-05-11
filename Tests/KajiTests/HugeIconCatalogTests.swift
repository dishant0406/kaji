import Testing
@testable import Kaji

struct HugeIconCatalogTests {
    @Test func extractsGlyphValueFromHugeiconsCSS() {
        let css = ".hgi-stroke.hgi-add-01:before{content:\"A\"}.hgi-stroke.hgi-sidebar-left-01:before{content:\"B\"}"
        #expect(HugeIconCatalog.glyphValue(for: "add-01", in: css) == "A")
        #expect(HugeIconCatalog.glyphValue(for: "sidebar-left-01", in: css) == "B")
    }
}
