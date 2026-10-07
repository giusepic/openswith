import Foundation

/// Scan status for the sidebar footer and the failure banner above the table.
///
/// A pure function of three store properties, kept out of the view so it can be
/// tested directly. The raw `Date` travels rather than a formatted string —
/// relative age is formatted at the point of display, which keeps these tests
/// free of locale and date-formatting flakiness.
enum BannerState: Equatable {
    /// Fresh data, nothing in flight.
    case hidden
    /// Probing with nothing on screen.
    case probing
    /// Probing while cached rows from `since` are visible.
    case refreshingFromCache(since: Date)
    /// The probe failed and there is nothing to show.
    case failed(reason: String)
    /// The probe failed but cached rows from `since` are still on screen.
    case failedShowingCache(since: Date)

    static func resolve(isLoading: Bool,
                        failureReason: String?,
                        cacheCapturedAt: Date?) -> BannerState {
        if isLoading {
            // A probe in flight is the more useful signal than a previous failure.
            if let capturedAt = cacheCapturedAt { return .refreshingFromCache(since: capturedAt) }
            return .probing
        }
        if let reason = failureReason {
            if let capturedAt = cacheCapturedAt { return .failedShowingCache(since: capturedAt) }
            return .failed(reason: reason)
        }
        return .hidden
    }
}
