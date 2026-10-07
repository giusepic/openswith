import XCTest
@testable import OpensWith

final class ProbeSmokeTests: XCTestCase {
    func test_enumerateReturnsManyEntries() async {
        let result = await LaunchServicesProbe.enumerate()
        XCTAssertGreaterThan(result.entries.count, 100,
            "Expected enumeration to find many extensions; got \(result.entries.count). Failure: \(result.failureReason ?? "none")")
        XCTAssertTrue(result.entries.contains { $0.displayName == ".pdf" })
        XCTAssertNil(result.failureReason)
    }

    func test_pdfResolvesToCanonicalUTI() async {
        let result = await LaunchServicesProbe.enumerate()
        let pdf = result.entries.first { $0.displayName == ".pdf" }
        XCTAssertEqual(pdf?.uti, "com.adobe.pdf",
            "PDF must resolve to the system's canonical UTI, not an arbitrary app-private UTI from lsregister.")
    }

    /// `LSCopyAllRoleHandlersForContentType` returns *every* handler, including
    /// the default one, so the probe has to subtract the default itself —
    /// otherwise the detail pane lists the default app twice.
    func test_alternativesNeverIncludeTheDefaultApp() async {
        let result = await LaunchServicesProbe.enumerate()
        let offenders = result.entries.filter { entry in
            guard let defaultID = entry.defaultApp?.bundleID else { return false }
            return entry.alternativeApps.contains { $0.bundleID == defaultID }
        }
        XCTAssertTrue(offenders.isEmpty,
            "These entries list their own default among the alternatives: "
            + offenders.prefix(5).map(\.displayName).joined(separator: ", "))
    }

    /// URL schemes have no UTI, so the probe assigns their category directly
    /// rather than going through `Categorizer`.
    func test_urlSchemeEntriesAreCategorisedAsURLSchemes() async {
        let result = await LaunchServicesProbe.enumerate()
        let schemes = result.entries.filter { $0.kind == .urlScheme }
        XCTAssertFalse(schemes.isEmpty, "Expected the dump to yield at least one URL scheme.")
        XCTAssertTrue(schemes.allSatisfy { $0.category == .urlSchemes })
    }

    func test_reresolve_preservesIdentityFields() {
        let stale = HandlerEntry(
            id: "ext:.pdf", displayName: ".pdf", kind: .fileExtension,
            uti: "com.adobe.pdf",
            defaultApp: AppRef(bundleID: "com.stale.App", displayName: "Stale",
                               bundleURL: nil, exists: false),
            alternativeApps: [], category: .documents
        )

        let fresh = LaunchServicesProbe.reresolve(entry: stale)

        XCTAssertEqual(fresh.id, stale.id)
        XCTAssertEqual(fresh.displayName, stale.displayName)
        XCTAssertEqual(fresh.kind, stale.kind)
        // Re-resolved from the system, so it should no longer be the stale app.
        XCTAssertNotEqual(fresh.defaultApp?.bundleID, "com.stale.App")
    }

    func test_reresolve_handlesURLSchemes() {
        let stale = HandlerEntry(
            id: "url:mailto", displayName: "mailto:", kind: .urlScheme,
            uti: nil, defaultApp: nil, alternativeApps: [], category: .urlSchemes
        )

        let fresh = LaunchServicesProbe.reresolve(entry: stale)

        XCTAssertEqual(fresh.id, "url:mailto")
        XCTAssertEqual(fresh.kind, .urlScheme)
        XCTAssertEqual(fresh.category, .urlSchemes)
    }
}
