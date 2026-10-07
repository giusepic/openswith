import XCTest
@testable import OpensWith

final class SemanticVersionTests: XCTestCase {

    // MARK: - Parsing

    func test_parsesPlainTriple() {
        let v = SemanticVersion("1.2.3")
        XCTAssertEqual(v?.components, [1, 2, 3])
    }

    /// GitHub tags are conventionally `v`-prefixed; the plist version never is.
    /// Both must land on the same value or every comparison is garbage.
    func test_stripsLeadingV() {
        XCTAssertEqual(SemanticVersion("v1.2.3"), SemanticVersion("1.2.3"))
        XCTAssertEqual(SemanticVersion("V1.2.3"), SemanticVersion("1.2.3"))
    }

    func test_trimsSurroundingWhitespace() {
        XCTAssertEqual(SemanticVersion("  1.2.3 \n"), SemanticVersion("1.2.3"))
    }

    func test_acceptsAnyComponentCount() {
        XCTAssertEqual(SemanticVersion("2")?.components, [2])
        XCTAssertEqual(SemanticVersion("2.1")?.components, [2, 1])
        XCTAssertEqual(SemanticVersion("2.1.0.4")?.components, [2, 1, 0, 4])
    }

    func test_rejectsUnparseableInput() {
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("v"))
        XCTAssertNil(SemanticVersion("latest"))
        XCTAssertNil(SemanticVersion("1.2.x"))
        XCTAssertNil(SemanticVersion("1..2"))
        XCTAssertNil(SemanticVersion("-1.0.0"))
        XCTAssertNil(SemanticVersion("release-2024"))
    }

    /// Pre-release and build suffixes aren't part of this app's tagging scheme.
    /// Rejecting them keeps the parser honest rather than silently reading
    /// "1.0.0-beta" as 1.0.0 and telling a beta user they're up to date.
    func test_rejectsPreReleaseAndBuildSuffixes() {
        XCTAssertNil(SemanticVersion("1.0.0-beta"))
        XCTAssertNil(SemanticVersion("1.0.0+build7"))
    }

    // MARK: - Comparison

    /// The whole reason this type exists instead of comparing strings:
    /// lexically "0.10.0" sorts *below* "0.9.0", which would silently stop
    /// announcing updates after the ninth minor release.
    func test_comparesNumericallyNotLexically() {
        XCTAssertLessThan(SemanticVersion("0.9.0")!, SemanticVersion("0.10.0")!)
        XCTAssertLessThan(SemanticVersion("1.9.0")!, SemanticVersion("1.10.0")!)
        XCTAssertLessThan(SemanticVersion("2.0.0")!, SemanticVersion("10.0.0")!)
    }

    func test_comparesMajorBeforeMinorBeforePatch() {
        XCTAssertLessThan(SemanticVersion("1.0.0")!, SemanticVersion("2.0.0")!)
        XCTAssertLessThan(SemanticVersion("1.1.0")!, SemanticVersion("1.2.0")!)
        XCTAssertLessThan(SemanticVersion("1.1.1")!, SemanticVersion("1.1.2")!)
        XCTAssertGreaterThan(SemanticVersion("2.0.0")!, SemanticVersion("1.99.99")!)
    }

    /// Short forms are padded with zeros, so "1.0" and "1.0.0" are the same
    /// release and neither looks newer than the other.
    func test_padsUnequalComponentCounts() {
        XCTAssertEqual(SemanticVersion("1.0"), SemanticVersion("1.0.0"))
        XCTAssertEqual(SemanticVersion("1"), SemanticVersion("1.0.0"))
        XCTAssertLessThan(SemanticVersion("1.0")!, SemanticVersion("1.0.1")!)
        XCTAssertGreaterThan(SemanticVersion("1.1")!, SemanticVersion("1.0.9")!)
    }

    func test_equalVersionsAreNotLessThan() {
        XCTAssertFalse(SemanticVersion("1.2.3")! < SemanticVersion("1.2.3")!)
        XCTAssertEqual(SemanticVersion("1.2.3"), SemanticVersion("v1.2.3"))
    }

    // MARK: - The shipped scenario

    /// Shipping 1.0.0 while the newest tag is v0.3.0 must read as up to date,
    /// not as an available "update" that moves the user backwards.
    func test_shippedVersionAheadOfLatestTagIsNotAnUpdate() {
        let shipped = SemanticVersion("1.0.0")!
        let latestTag = SemanticVersion("v0.3.0")!
        XCTAssertGreaterThan(shipped, latestTag)
        XCTAssertFalse(latestTag > shipped)
    }
}
