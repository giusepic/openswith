import XCTest
import UniformTypeIdentifiers
@testable import OpensWith

/// Stands in for NSWorkspace. Calling the real one in a test would pop the OS
/// consent dialog on the developer's machine and mutate their actual defaults.
private final class StubWorkspace: WorkspaceWriting, @unchecked Sendable {
    var setError: Error?
    /// What a read-back should report, as a bundle ID. nil means "no handler".
    var readBackBundleID: String?
    /// Set true to fire the completion handler twice — the double-resume case.
    var fireCompletionTwice = false

    private(set) var setCallCount = 0
    private(set) var lastRequestedAppURL: URL?

    func setDefaultApplication(at appURL: URL,
                               toOpen type: UTType,
                               completion: @escaping (Error?) -> Void) {
        setCallCount += 1
        lastRequestedAppURL = appURL
        completion(setError)
        if fireCompletionTwice { completion(setError) }
    }

    func setDefaultApplication(at appURL: URL,
                               toOpenURLsWithScheme scheme: String,
                               completion: @escaping (Error?) -> Void) {
        setCallCount += 1
        lastRequestedAppURL = appURL
        completion(setError)
        if fireCompletionTwice { completion(setError) }
    }

    func currentDefaultBundleID(for entry: HandlerEntry) -> String? {
        readBackBundleID
    }
}

@MainActor
final class DefaultsWriterTests: XCTestCase {

    private func makeApp(_ bundleID: String) -> AppRef {
        AppRef(bundleID: bundleID,
               displayName: bundleID,
               bundleURL: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
               exists: true)
    }

    private func extensionEntry(uti: String? = "public.jpeg") -> HandlerEntry {
        HandlerEntry(id: "ext:.jpg", displayName: ".jpg", kind: .fileExtension,
                     uti: uti, defaultApp: makeApp("com.apple.Preview"),
                     alternativeApps: [], category: .images)
    }

    private func schemeEntry() -> HandlerEntry {
        HandlerEntry(id: "url:mailto", displayName: "mailto:", kind: .urlScheme,
                     uti: nil, defaultApp: makeApp("com.apple.mail"),
                     alternativeApps: [], category: .urlSchemes)
    }

    func test_nilErrorAndMatchingReadBack_isApplied() async {
        let workspace = StubWorkspace()
        workspace.setError = nil
        workspace.readBackBundleID = "com.google.Chrome"
        let writer = SystemDefaultsWriter(workspace: workspace)

        let target = makeApp("com.google.Chrome")
        let outcome = await writer.setDefault(app: target, for: extensionEntry())

        XCTAssertEqual(outcome, .applied(target))
    }

    func test_nilErrorButReadBackDiffers_isRefused() async {
        let workspace = StubWorkspace()
        workspace.setError = nil
        // Reported success, but the system still says Preview owns it.
        workspace.readBackBundleID = "com.apple.Preview"
        let writer = SystemDefaultsWriter(workspace: workspace)

        let outcome = await writer.setDefault(app: makeApp("com.google.Chrome"),
                                              for: extensionEntry())

        XCTAssertEqual(outcome, .refused)
    }

    func test_nilErrorAndNoHandlerAtAll_isRefused() async {
        let workspace = StubWorkspace()
        workspace.setError = nil
        workspace.readBackBundleID = nil
        let writer = SystemDefaultsWriter(workspace: workspace)

        let outcome = await writer.setDefault(app: makeApp("com.google.Chrome"),
                                              for: extensionEntry())

        XCTAssertEqual(outcome, .refused)
    }

    func test_cocoaError256_isDeclined_notFailed() async {
        let workspace = StubWorkspace()
        // Exactly what macOS returns when the user clicks "Keep <app>".
        workspace.setError = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [
            NSLocalizedDescriptionKey: "The file couldn’t be opened."
        ])
        let writer = SystemDefaultsWriter(workspace: workspace)

        let outcome = await writer.setDefault(app: makeApp("com.google.Chrome"),
                                              for: extensionEntry())

        XCTAssertEqual(outcome, .declined)
    }

    /// The misleading string must never reach the user.
    func test_declined_doesNotCarryTheSystemsMisleadingMessage() async {
        let workspace = StubWorkspace()
        workspace.setError = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [
            NSLocalizedDescriptionKey: "The file couldn’t be opened."
        ])
        let writer = SystemDefaultsWriter(workspace: workspace)

        let outcome = await writer.setDefault(app: makeApp("com.google.Chrome"),
                                              for: extensionEntry())

        if case .failed(let reason) = outcome {
            XCTFail("Decline surfaced as a failure carrying: \(reason)")
        }
    }

    func test_otherError_isFailedAndCarriesTheDescription() async {
        let workspace = StubWorkspace()
        workspace.setError = NSError(domain: NSCocoaErrorDomain, code: 260, userInfo: [
            NSLocalizedDescriptionKey: "The file couldn’t be opened because it doesn’t exist."
        ])
        let writer = SystemDefaultsWriter(workspace: workspace)

        let outcome = await writer.setDefault(app: makeApp("com.google.Chrome"),
                                              for: extensionEntry())

        XCTAssertEqual(outcome,
                       .failed(reason: "The file couldn’t be opened because it doesn’t exist."))
    }

    /// 256 in a *different* domain is not the decline signal.
    func test_code256InAnotherDomain_isFailed() async {
        let workspace = StubWorkspace()
        workspace.setError = NSError(domain: "SomeOtherDomain", code: 256, userInfo: [
            NSLocalizedDescriptionKey: "Something else entirely."
        ])
        let writer = SystemDefaultsWriter(workspace: workspace)

        let outcome = await writer.setDefault(app: makeApp("com.google.Chrome"),
                                              for: extensionEntry())

        XCTAssertEqual(outcome, .failed(reason: "Something else entirely."))
    }

    func test_urlSchemeEntry_routesToTheSchemeOverload() async {
        let workspace = StubWorkspace()
        workspace.setError = nil
        workspace.readBackBundleID = "com.google.Chrome"
        let writer = SystemDefaultsWriter(workspace: workspace)

        let target = makeApp("com.google.Chrome")
        // schemeEntry() has uti == nil, as every URL scheme entry does.
        let outcome = await writer.setDefault(app: target, for: schemeEntry())

        XCTAssertEqual(outcome, .applied(target))
        XCTAssertEqual(workspace.setCallCount, 1)
    }

    /// The completion handler is OS-owned and blocks on a human. A double call
    /// must not trap the CheckedContinuation and take the app down.
    func test_doubleCompletionCallback_doesNotTrap() async {
        let workspace = StubWorkspace()
        workspace.setError = nil
        workspace.readBackBundleID = "com.google.Chrome"
        workspace.fireCompletionTwice = true
        let writer = SystemDefaultsWriter(workspace: workspace)

        let target = makeApp("com.google.Chrome")
        let outcome = await writer.setDefault(app: target, for: extensionEntry())

        XCTAssertEqual(outcome, .applied(target))
    }

    /// "Not assigned" rows genuinely exist in the table: UTType(filenameExtension:)
    /// returned nil for them at probe time.
    func test_fileExtensionWithNilUTI_failsWithoutCallingTheSystem() async {
        let workspace = StubWorkspace()
        let writer = SystemDefaultsWriter(workspace: workspace)

        let outcome = await writer.setDefault(app: makeApp("com.google.Chrome"),
                                              for: extensionEntry(uti: nil))

        XCTAssertEqual(workspace.setCallCount, 0)
        guard case .failed = outcome else {
            return XCTFail("Expected .failed, got \(outcome)")
        }
    }

    /// An unusable entry is a genuine failure the user must see. Classifying it
    /// as `.declined` would show them nothing at all — the decline path is silent
    /// by design, because it describes a choice they made.
    func test_unusableEntry_isNotClassifiedAsDeclined() async {
        let workspace = StubWorkspace()
        let writer = SystemDefaultsWriter(workspace: workspace)

        for entry in [extensionEntry(uti: nil),
                      extensionEntry(uti: ""),
                      HandlerEntry(id: "url:", displayName: ":", kind: .urlScheme,
                                   uti: nil, defaultApp: nil,
                                   alternativeApps: [], category: .urlSchemes)] {
            let outcome = await writer.setDefault(app: makeApp("com.google.Chrome"),
                                                  for: entry)

            XCTAssertNotEqual(outcome, .declined,
                              "\(entry.id) reported as a user decline and would show nothing")
            guard case .failed(let reason) = outcome else {
                return XCTFail("Expected .failed for \(entry.id), got \(outcome)")
            }
            XCTAssertFalse(reason.isEmpty, "\(entry.id) failed with no explanation")
        }
    }

    /// A stale cache or a dynamic UTI can yield a string UTType cannot build.
    func test_fileExtensionWithUnconstructibleUTI_failsWithoutCallingTheSystem() async {
        let workspace = StubWorkspace()
        let writer = SystemDefaultsWriter(workspace: workspace)

        let outcome = await writer.setDefault(
            app: makeApp("com.google.Chrome"),
            for: extensionEntry(uti: "")
        )

        XCTAssertEqual(workspace.setCallCount, 0)
        guard case .failed = outcome else {
            return XCTFail("Expected .failed, got \(outcome)")
        }
    }

    func test_appWithNoBundleURL_failsWithoutCallingTheSystem() async {
        let workspace = StubWorkspace()
        let writer = SystemDefaultsWriter(workspace: workspace)
        let ghost = AppRef(bundleID: "com.gone.App", displayName: "Gone",
                           bundleURL: nil, exists: false)

        let outcome = await writer.setDefault(app: ghost, for: extensionEntry())

        XCTAssertEqual(workspace.setCallCount, 0)
        guard case .failed = outcome else {
            return XCTFail("Expected .failed, got \(outcome)")
        }
    }
}
