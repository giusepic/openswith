import XCTest
@testable import OpensWith

final class CategorizerTests: XCTestCase {
    func test_imageUTIs() {
        XCTAssertEqual(Categorizer.categorize(uti: "public.jpeg"), .images)
        XCTAssertEqual(Categorizer.categorize(uti: "public.heic"), .images)
    }

    func test_textUTIs() {
        XCTAssertEqual(Categorizer.categorize(uti: "public.plain-text"), .codeText)
        XCTAssertEqual(Categorizer.categorize(uti: "net.daringfireball.markdown"), .codeText)
    }

    func test_sourceCodeUTIs() {
        XCTAssertEqual(Categorizer.categorize(uti: "public.swift-source"), .codeText)
        XCTAssertEqual(Categorizer.categorize(uti: "public.python-script"), .codeText)
    }

    func test_documentUTIs() {
        XCTAssertEqual(Categorizer.categorize(uti: "com.adobe.pdf"), .documents)
    }

    /// RTF conforms to both `.rtf` and `.text`, so it only lands in Documents
    /// because the documents branch is checked before the text branch.
    func test_rtfIsADocumentNotText() {
        XCTAssertEqual(Categorizer.categorize(uti: "public.rtf"), .documents)
    }

    func test_audioUTIs() {
        XCTAssertEqual(Categorizer.categorize(uti: "public.mp3"), .audio)
    }

    func test_videoUTIs() {
        XCTAssertEqual(Categorizer.categorize(uti: "public.mpeg-4"), .video)
        XCTAssertEqual(Categorizer.categorize(uti: "com.apple.quicktime-movie"), .video)
    }

    func test_archiveUTIs() {
        XCTAssertEqual(Categorizer.categorize(uti: "public.zip-archive"), .archives)
    }

    func test_unknownUTIFallsBackToOther() {
        XCTAssertEqual(Categorizer.categorize(uti: "com.acme.proprietary-format"), .other)
        XCTAssertEqual(Categorizer.categorize(uti: nil), .other)
    }
}
