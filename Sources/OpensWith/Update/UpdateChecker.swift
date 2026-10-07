import Foundation
import SwiftUI

/// What the UI should be showing about updates right now.
enum UpdateState: Equatable {
    /// Nothing to say. The automatic check collapses to this for every
    /// outcome except "there is a newer version".
    case idle
    case checking
    case available(Release)
    /// Only ever reached by an explicit check — the menu item's whole purpose.
    case upToDate
    /// Offline, rate-limited, private repo, unparseable tag, or no bundle
    /// version to compare against. All indistinguishable to the user.
    case unavailable
}

/// Owns the update-check state machine: when to ask, and how much of the
/// answer the user is allowed to see.
///
/// Two rules shape everything here:
///
/// 1. **The automatic check may only ever surface good news.** An update
///    exists, or the app says nothing. "You're up to date" on every launch is
///    noise, and a network error the user can't act on is worse than silence.
/// 2. **The manual check reports everything**, because the user asked. A menu
///    item that does nothing visible when you're current looks broken.
///
/// Kept entirely separate from `AppStore`, which is about Launch Services and
/// has no business knowing about releases.
@MainActor
final class UpdateChecker: ObservableObject {

    @Published private(set) var state: UpdateState = .idle

    static let lastCheckedKey = "UpdateChecker.lastCheckedAt"
    static let skippedVersionKey = "UpdateChecker.skippedVersion"

    /// One check a day is plenty for an app shipped as a manual download.
    private static let throttleInterval: TimeInterval = 24 * 60 * 60

    private let currentVersion: String?
    private let fetcher: ReleaseFetching
    private let defaults: UserDefaults

    /// `currentVersion` is nil under `swift run`, which has no bundle and so no
    /// `CFBundleShortVersionString`. That's a supported dev path, not an error:
    /// it means the comparison can't be made, so the checker reports
    /// `.unavailable` when asked and stays silent otherwise.
    init(currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
         fetcher: ReleaseFetching = GitHubReleaseFetcher(),
         defaults: UserDefaults = .standard) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
        self.defaults = defaults
    }

    // MARK: - Entry points

    /// Runs on launch. Throttled, silent about everything except an available
    /// update, and respects a previous dismissal.
    func checkAutomatically() async {
        guard !isThrottled else { return }

        let outcome = await resolveOutcome()
        recordCheckTime()

        switch outcome {
        case .available(let release) where !isSkipped(release):
            state = .available(release)
        default:
            state = .idle
        }
    }

    /// Runs from the menu. Ignores the throttle and any dismissal, and reports
    /// whatever it finds — including that there's nothing new.
    func checkManually() async {
        state = .checking
        let outcome = await resolveOutcome()
        recordCheckTime()
        state = outcome
    }

    /// Hides this specific version for good. Stored as the skipped tag rather
    /// than a boolean, so the *next* release still gets announced.
    func dismissCurrentRelease() {
        if case .available(let release) = state {
            defaults.set(release.tagName, forKey: Self.skippedVersionKey)
        }
        state = .idle
    }

    /// Clears a transient `.upToDate` / `.unavailable` message. Those answer a
    /// question the user asked a moment ago and shouldn't linger.
    func clearTransientState() {
        if state == .upToDate || state == .unavailable {
            state = .idle
        }
    }

    // MARK: - Internals

    private func resolveOutcome() async -> UpdateState {
        guard let currentVersion,
              let current = SemanticVersion(currentVersion)
        else { return .unavailable }

        guard let release = await fetcher.latestRelease(),
              let latest = SemanticVersion(release.tagName)
        else { return .unavailable }

        return latest > current ? .available(release) : .upToDate
    }

    private var isThrottled: Bool {
        guard let last = defaults.object(forKey: Self.lastCheckedKey) as? Date else {
            return false
        }
        let elapsed = Date().timeIntervalSince(last)
        // A negative interval means the clock moved backwards; treat that as
        // "due" rather than locking the check out until the date catches up.
        return elapsed >= 0 && elapsed < Self.throttleInterval
    }

    private func recordCheckTime() {
        defaults.set(Date(), forKey: Self.lastCheckedKey)
    }

    private func isSkipped(_ release: Release) -> Bool {
        defaults.string(forKey: Self.skippedVersionKey) == release.tagName
    }
}
