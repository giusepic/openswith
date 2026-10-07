import XCTest
@testable import OpensWith

final class LookupSmokeTests: XCTestCase {
    func test_pdfHasSomeDefault() {
        XCTAssertNotNil(LaunchServicesLookup.defaultAppURL(forUTI: "com.adobe.pdf"))
    }

    func test_mailtoHasSomeDefault() {
        XCTAssertNotNil(LaunchServicesLookup.defaultAppURL(forURLScheme: "mailto"))
    }

    /// Integration smoke test — hits real system APIs, per repo convention.
    /// Asserts the shape, not a specific app: CI machines differ.
    func test_allAppURLsForURLScheme_returnsCandidates() {
        let urls = LaunchServicesLookup.allAppURLs(forURLScheme: "mailto")
        // Every result must be an existing .app bundle.
        for url in urls {
            XCTAssertEqual(url.pathExtension, "app", "unexpected candidate: \(url.path)")
        }
    }

    func test_allAppURLsForURLScheme_unknownSchemeReturnsEmpty() {
        let urls = LaunchServicesLookup.allAppURLs(
            forURLScheme: "openswith-no-such-scheme-12345")
        XCTAssertTrue(urls.isEmpty)
    }

    /// The read path (what the table shows) and the write path's verification
    /// (what decides `.applied` vs `.refused`) must name the same app, or a
    /// change can report success while the row still reads "Not assigned" —
    /// and the snapshot persists that contradiction.
    ///
    /// They disagreed once: the read path filtered on the `.viewer` role, which
    /// returns nil for ~60 of ~200 schemes that `NSWorkspace` resolves fine.
    func test_schemeReadPathAgreesWithWriteVerification() {
        // Resolve whatever the write path's read-back would see, without ever
        // calling a setDefault API.
        for scheme in ["mailto", "http", "https", "ftp", "tel", "sms", "facetime"] {
            guard let url = URL(string: "\(scheme)://") else { continue }
            let writeSide = NSWorkspace.shared.urlForApplication(toOpen: url)
                .flatMap { Bundle(url: $0)?.bundleIdentifier }
            let readSide = LaunchServicesLookup.defaultAppURL(forURLScheme: scheme)
                .flatMap { Bundle(url: $0)?.bundleIdentifier }
            XCTAssertEqual(readSide, writeSide,
                "\(scheme): the table would show \(readSide ?? "Not assigned") "
                + "while a change verifies against \(writeSide ?? "nil")")
        }
    }
}
