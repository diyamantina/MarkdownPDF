@testable import MarkdownPDF
import Testing

/// Oracle: the fit rule's closed form, `scale = min(W / w, H / h)` with centring and
/// a 0.1% aspect snap, evaluated here by hand for each case.
@Suite("Cover fit")
struct PDFCoverFitTests {
    private let page = PDFOptions.PageSize(width: 200, height: 400)

    private func fit(_ width: Int, _ height: Int) -> PDFCoverFit.Rectangle {
        PDFCoverFit.rectangle(imageWidth: width, imageHeight: height, page: page)
    }

    @Test("Equal aspect ratios fill the page, at any pixel size")
    func equalAspect() {
        let full = PDFCoverFit.Rectangle(x: 0, y: 0, width: 200, height: 400)
        #expect(fit(1, 2) == full)
        #expect(fit(1000, 2000) == full)
        #expect(fit(3, 6) == full)
    }

    @Test("The snap is 0.1% of the aspect ratio: inside fills, outside letterboxes")
    func snapBoundary() {
        let full = PDFCoverFit.Rectangle(x: 0, y: 0, width: 200, height: 400)
        // Aspect ratio 1000 : 1999 is 0.05% narrower than 1 : 2, so it snaps.
        #expect(fit(1000, 1999) == full)
        // 1000 : 2004 is 0.2% narrower, so the height decides and bars remain.
        let narrow = fit(1000, 2004)
        #expect(narrow != full)
        #expect(abs(narrow.height - 400) < 1e-9)
        #expect(abs(narrow.width - 1000.0 * 400 / 2004) < 1e-9)
        #expect(abs(narrow.x - (200 - narrow.width) / 2) < 1e-9)
    }

    @Test("Wide and tall images keep their aspect ratio and are centred")
    func letterboxAndPillarbox() {
        let wide = fit(40, 10)
        #expect(wide == PDFCoverFit.Rectangle(x: 0, y: 175, width: 200, height: 50))
        let tall = fit(10, 40)
        #expect(tall == PDFCoverFit.Rectangle(x: 50, y: 0, width: 100, height: 400))
    }

    @Test("Images scale up as well as down")
    func scalesUp() {
        #expect(fit(1, 1) == PDFCoverFit.Rectangle(x: 0, y: 100, width: 200, height: 200))
        #expect(fit(4000, 4000) == PDFCoverFit.Rectangle(x: 0, y: 100, width: 200, height: 200))
    }

    @Test("Degenerate sizes fill the page instead of dividing by zero", arguments: [(0, 10), (10, 0), (0, 0), (-1, 5)])
    func degenerate(width: Int, height: Int) {
        #expect(fit(width, height) == PDFCoverFit.Rectangle(x: 0, y: 0, width: 200, height: 400))
        let empty = PDFCoverFit.rectangle(imageWidth: 5, imageHeight: 5, page: .init(width: 0, height: 0))
        #expect(empty == PDFCoverFit.Rectangle(x: 0, y: 0, width: 0, height: 0))
    }
}
