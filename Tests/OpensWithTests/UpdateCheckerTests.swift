import XCTest
@testable import OpensWith

@MainActor
final class UpdateCheckerTests: XCTestCase {

    // MARK: - Doubles

    private struct StubFetcher: ReleaseFetching {
        let release: Release?
        func latestRelease() async -> Release? { release }
    }

    private static func release(_ tag: String) -> Release {
        Release(tagName: tag,
                url: URL(string: "https://github.com/giusepic/openswith/releases/tag/\(tag)")!)
    }

    /// A fresh suite per test, so throttle and skip state can't leak between them.
    private func makeDefaults() -> UserDefaults {
        let name = "UpdateCheckerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeChecker(current: String? = "1.0.0",
                             latest: String? = "2.0.0",
                             defaults: UserDefaults? = nil) -> UpdateChecker {
        UpdateChecker(currentVersion: current,
                      fetcher: StubFetcher(release: latest.map { Self.release($0) }),
                      defaults: defaults ?? makeDefaults())
    }

    // MARK: - Comparison outcomes

    func test_newerReleaseIsAvailable() async {
        let checker = makeChecker(current: "1.0.0", latest: "v2.0.0")
        await checker.checkManually()
        guard case .available(let release) = checker.state else {
            return XCTFail("expected .available, got \(checker.state)")
        }
        XCTAssertEqual(release.tagName, "v2.0.0")
    }

    func test_sameVersionIsUpToDate() async {
        let checker = makeChecker(current: "1.0.0", latest: "v1.0.0")
        await checker.checkManually()
        XCTAssertEqual(checker.state, .upToDate)
    }

    /// Shipping ahead of the newest tag — the state this app is in today, at
    /// 1.0.0 with v0.3.0 the latest tag — must never offer a downgrade.
    func test_olderReleaseIsUpToDate() async {
        let checker = makeChecker(current: "1.0.0", latest: "v0.3.0")
        await checker.checkManually()
        XCTAssertEqual(checker.state, .upToDate)
    }

    func test_fetchFailureIsUnavailable() async {
        let checker = makeChecker(latest: nil)
        await checker.checkManually()
        XCTAssertEqual(checker.state, .unavailable)
    }

    func test_unparseableTagIsUnavailable() async {
        let checker = makeChecker(current: "1.0.0", latest: "nightly")
        await checker.checkManually()
        XCTAssertEqual(checker.state, .unavailable)
    }

    /// Under `swift run` there is no bundle and so no version string. Comparing
    /// against nothing can only produce a wrong answer, so don't try.
    func test_missingCurrentVersionIsUnavailable() async {
        let checker = makeChecker(current: nil, latest: "v2.0.0")
        await checker.checkManually()
        XCTAssertEqual(checker.state, .unavailable)
    }

    // MARK: - Automatic vs manual

    /// The automatic check is allowed exactly one outcome the user can see.
    /// "You're up to date" unprompted on every launch is noise.
    func test_automaticCheckStaysSilentWhenUpToDate() async {
        let checker = makeChecker(current: "1.0.0", latest: "v1.0.0")
        await checker.checkAutomatically()
        XCTAssertEqual(checker.state, .idle)
    }

    func test_automaticCheckStaysSilentOnFailure() async {
        let checker = makeChecker(latest: nil)
        await checker.checkAutomatically()
        XCTAssertEqual(checker.state, .idle)
    }

    func test_automaticCheckSurfacesAnAvailableUpdate() async {
        let checker = makeChecker(current: "1.0.0", latest: "v2.0.0")
        await checker.checkAutomatically()
        guard case .available = checker.state else {
            return XCTFail("expected .available, got \(checker.state)")
        }
    }

    /// The manual check is the only reason the menu item exists — it has to
    /// report the boring answers too.
    func test_manualCheckReportsUpToDate() async {
        let checker = makeChecker(current: "1.0.0", latest: "v1.0.0")
        await checker.checkManually()
        XCTAssertEqual(checker.state, .upToDate)
    }

    // MARK: - Throttling

    func test_automaticCheckIsThrottledWithin24Hours() async {
        let defaults = makeDefaults()
        let first = makeChecker(current: "1.0.0", latest: "v2.0.0", defaults: defaults)
        await first.checkAutomatically()
        guard case .available = first.state else {
            return XCTFail("first check should have run")
        }

        let second = makeChecker(current: "1.0.0", latest: "v2.0.0", defaults: defaults)
        await second.checkAutomatically()
        XCTAssertEqual(second.state, .idle, "second launch within 24h should not re-check")
    }

    func test_automaticCheckRunsAgainAfter24Hours() async {
        let defaults = makeDefaults()
        let stale = Date().addingTimeInterval(-25 * 60 * 60)
        defaults.set(stale, forKey: UpdateChecker.lastCheckedKey)

        let checker = makeChecker(current: "1.0.0", latest: "v2.0.0", defaults: defaults)
        await checker.checkAutomatically()
        guard case .available = checker.state else {
            return XCTFail("expected .available after the throttle expired")
        }
    }

    /// A throttled automatic check must not block the user asking directly.
    func test_manualCheckIgnoresTheThrottle() async {
        let defaults = makeDefaults()
        defaults.set(Date(), forKey: UpdateChecker.lastCheckedKey)

        let checker = makeChecker(current: "1.0.0", latest: "v2.0.0", defaults: defaults)
        await checker.checkManually()
        guard case .available = checker.state else {
            return XCTFail("manual check should run regardless of the throttle")
        }
    }

    // MARK: - Dismissal

    func test_dismissingHidesThatVersion() async {
        let defaults = makeDefaults()
        let checker = makeChecker(current: "1.0.0", latest: "v2.0.0", defaults: defaults)
        await checker.checkManually()
        checker.dismissCurrentRelease()
        XCTAssertEqual(checker.state, .idle)

        // Expire the throttle, so `.idle` below can only mean "dismissed" and
        // not "didn't check" — otherwise this assertion passes either way.
        defaults.set(Date().addingTimeInterval(-25 * 60 * 60), forKey: UpdateChecker.lastCheckedKey)

        let relaunch = makeChecker(current: "1.0.0", latest: "v2.0.0", defaults: defaults)
        await relaunch.checkAutomatically()
        XCTAssertEqual(relaunch.state, .idle, "a dismissed version should stay dismissed")
    }

    /// Dismissal is per-version, not a global mute — the point of storing the
    /// skipped tag rather than a boolean.
    func test_dismissingOneVersionStillSurfacesTheNext() async {
        let defaults = makeDefaults()
        let checker = makeChecker(current: "1.0.0", latest: "v2.0.0", defaults: defaults)
        await checker.checkManually()
        checker.dismissCurrentRelease()

        // The next release lands days later, so the throttle has long expired.
        // Without this the assertion would pass or fail on the throttle rather
        // than on the dismissal behaviour it's here to pin.
        defaults.set(Date().addingTimeInterval(-25 * 60 * 60), forKey: UpdateChecker.lastCheckedKey)

        let next = makeChecker(current: "1.0.0", latest: "v3.0.0", defaults: defaults)
        await next.checkAutomatically()
        guard case .available(let release) = next.state else {
            return XCTFail("expected .available, got \(next.state)")
        }
        XCTAssertEqual(release.tagName, "v3.0.0")
    }

    /// Asking explicitly overrides an earlier dismissal; otherwise the menu
    /// item would silently do nothing and look broken.
    func test_manualCheckIgnoresDismissal() async {
        let defaults = makeDefaults()
        let checker = makeChecker(current: "1.0.0", latest: "v2.0.0", defaults: defaults)
        await checker.checkManually()
        checker.dismissCurrentRelease()

        let again = makeChecker(current: "1.0.0", latest: "v2.0.0", defaults: defaults)
        await again.checkManually()
        guard case .available = again.state else {
            return XCTFail("manual check should ignore a dismissal")
        }
    }
}
