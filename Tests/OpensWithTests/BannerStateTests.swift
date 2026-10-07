import XCTest
@testable import OpensWith

final class BannerStateTests: XCTestCase {

    private let captured = Date(timeIntervalSince1970: 1_759_395_272)

    func test_idleWithFreshDataIsHidden() {
        XCTAssertEqual(
            BannerState.resolve(isLoading: false, failureReason: nil, cacheCapturedAt: nil),
            .hidden
        )
    }

    func test_loadingWithNothingCachedIsProbing() {
        XCTAssertEqual(
            BannerState.resolve(isLoading: true, failureReason: nil, cacheCapturedAt: nil),
            .probing
        )
    }

    func test_loadingWithCachedRowsOnScreenIsRefreshingFromCache() {
        XCTAssertEqual(
            BannerState.resolve(isLoading: true, failureReason: nil, cacheCapturedAt: captured),
            .refreshingFromCache(since: captured)
        )
    }

    func test_failedWithNothingOnScreenIsFailed() {
        XCTAssertEqual(
            BannerState.resolve(isLoading: false, failureReason: "boom", cacheCapturedAt: nil),
            .failed(reason: "boom")
        )
    }

    func test_failedWithCachedRowsStillOnScreenIsFailedShowingCache() {
        XCTAssertEqual(
            BannerState.resolve(isLoading: false, failureReason: "boom", cacheCapturedAt: captured),
            .failedShowingCache(since: captured)
        )
    }

    /// `resolve` must be total. A refresh clears `failureReason` before probing,
    /// so this combination should not arise — but if it does, loading wins,
    /// because a probe is genuinely in flight and that is the more useful signal.
    func test_loadingTakesPrecedenceOverAStaleFailureReason() {
        XCTAssertEqual(
            BannerState.resolve(isLoading: true, failureReason: "boom", cacheCapturedAt: nil),
            .probing
        )
        XCTAssertEqual(
            BannerState.resolve(isLoading: true, failureReason: "boom", cacheCapturedAt: captured),
            .refreshingFromCache(since: captured)
        )
    }
}
