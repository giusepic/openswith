import XCTest
@testable import OpensWith

final class LSDumpParserTests: XCTestCase {
    private func loadFixture() throws -> String {
        let url = Bundle.module.url(forResource: "lsregister-mini", withExtension: "txt", subdirectory: "Fixtures")!
        return try String(contentsOf: url)
    }

    func test_parsesExtensionFromTypeStanza() throws {
        let result = LSDumpParser.parse(try loadFixture())
        XCTAssertTrue(result.extensions.contains(".pdf"))
    }

    func test_parsesEveryExtensionOnAMultiExtensionType() throws {
        let result = LSDumpParser.parse(try loadFixture())
        XCTAssertTrue(result.extensions.contains(".heic"))
        XCTAssertTrue(result.extensions.contains(".heif"))
    }

    /// `tags:` mixes extensions with MIME types, OSTypes and pasteboard names —
    /// only the dot-prefixed entries are extensions.
    func test_ignoresNonExtensionTags() throws {
        let result = LSDumpParser.parse(try loadFixture())
        XCTAssertFalse(result.extensions.contains { $0.contains("/") })
        XCTAssertFalse(result.extensions.contains { $0.contains("\"") })
    }

    func test_parsesUrlSchemesAcrossClaims() throws {
        let result = LSDumpParser.parse(try loadFixture())
        XCTAssertTrue(result.urlSchemes.contains("mailto"))
        XCTAssertTrue(result.urlSchemes.contains("tel"))
        XCTAssertTrue(result.urlSchemes.contains("sms"))
    }

    func test_emptyInput_returnsEmptyResult() {
        let result = LSDumpParser.parse("")
        XCTAssertTrue(result.extensions.isEmpty)
        XCTAssertTrue(result.urlSchemes.isEmpty)
    }

    func test_malformedStanza_isSkippedNotFatal() {
        let garbage = """
        --------------------------------------------------------------------------------
        type id:  broken
        no uti line here
        """
        XCTAssertNoThrow(LSDumpParser.parse(garbage))
    }
}
