import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var entries: [HandlerEntry] = [] {
        didSet { rebuildAppCache() }
    }
    @Published var browseMode: BrowseMode = .categories
    @Published var selectedFilter: BrowseFilter = .allCategories
    @Published var appSortKey: AppSortKey = .name
    @Published var appSortDirection: SortDirection = .ascending
    @Published var searchText: String = ""
    @Published var selectedEntryID: String? = nil {
        // A message about `.jpg` must not linger over `.png` — or over nothing.
        // Owned here rather than in `DetailView.onChange`, which sits inside the
        // `if let entry` branch and so never fires when the selection goes to nil.
        didSet { if selectedEntryID != oldValue { lastChangeOutcome = nil } }
    }
    @Published var isLoading: Bool = false
    @Published var failureReason: String? = nil

    /// Non-nil only while the rows on screen came from disk. A successful probe
    /// clears it, because the rows are live from that point on.
    @Published var cacheCapturedAt: Date? = nil

    /// Non-nil while a change is awaiting the user's answer in the OS dialog.
    /// The interface shows progress; the rest of the UI stays live, because the
    /// user may leave the dialog sitting indefinitely (measured: 9.5s, but
    /// unbounded in principle).
    @Published var pendingChangeEntryID: String? = nil

    /// The most recent change outcome, for inline display in the detail pane.
    @Published var lastChangeOutcome: ChangeOutcome? = nil

    // Injected so tests can stub the probe (the real one takes ~3.6s and cannot
    // be made to fail), redirect writes away from the developer's real
    // Application Support, and — critically — exercise changing a default
    // without triggering the OS consent dialog. All default to production.
    private let probe: () async -> ProbeResult
    private let snapshotDirectory: URL
    private let writer: DefaultsWriting
    private let reresolve: (HandlerEntry) -> HandlerEntry

    init(probe: @escaping () async -> ProbeResult = { await LaunchServicesProbe.enumerate() },
         snapshotDirectory: URL = SnapshotStore.defaultBaseDirectory,
         writer: DefaultsWriting = SystemDefaultsWriter(),
         reresolve: @escaping (HandlerEntry) -> HandlerEntry = { LaunchServicesProbe.reresolve(entry: $0) }) {
        self.probe = probe
        self.snapshotDirectory = snapshotDirectory
        self.writer = writer
        self.reresolve = reresolve
    }

    // Caches derived from `entries`, rebuilt in `rebuildAppCache()` on entries mutation.
    // Keeps `appsWithDefaults` and `count(for: .app(...))` from re-walking entries per access.
    private var dedupedDefaultApps: [AppRef] = []
    private var defaultCountByBundleID: [String: Int] = [:]

    var bannerState: BannerState {
        .resolve(isLoading: isLoading,
                 failureReason: failureReason,
                 cacheCapturedAt: cacheCapturedAt)
    }

    var filteredEntries: [HandlerEntry] {
        let byFilter: [HandlerEntry]
        switch selectedFilter {
        case .allCategories:
            byFilter = entries
        case .category(let c):
            byFilter = entries.filter { $0.category == c }
        case .app(let bundleID):
            byFilter = entries.filter { $0.defaultApp?.bundleID == bundleID }
        }
        guard !searchText.isEmpty else { return byFilter }
        let needle = searchText.lowercased()
        return byFilter.filter {
            $0.displayName.lowercased().contains(needle)
                || ($0.defaultApp?.displayName.lowercased().contains(needle) ?? false)
        }
    }

    var selectedEntry: HandlerEntry? {
        guard let id = selectedEntryID else { return nil }
        return entries.first { $0.id == id }
    }

    var appsWithDefaults: [AppRef] {
        let pairs: [(app: AppRef, count: Int)] = dedupedDefaultApps.map { app in
            (app, defaultCountByBundleID[app.bundleID, default: 0])
        }

        // Sort per appSortKey / appSortDirection. Tie-break: displayName ascending.
        let sorted = pairs.sorted { lhs, rhs in
            switch appSortKey {
            case .name:
                let cmp = lhs.app.displayName.localizedCaseInsensitiveCompare(rhs.app.displayName)
                if cmp == .orderedSame { return false }
                return appSortDirection == .ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            case .count:
                if lhs.count != rhs.count {
                    return appSortDirection == .ascending ? lhs.count < rhs.count : lhs.count > rhs.count
                }
                // Tie-break by displayName ascending, regardless of primary direction.
                return lhs.app.displayName.localizedCaseInsensitiveCompare(rhs.app.displayName) == .orderedAscending
            }
        }

        return sorted.map { $0.app }
    }

    func count(for filter: BrowseFilter) -> Int {
        switch filter {
        case .allCategories:
            return entries.count
        case .category(let c):
            return entries.filter { $0.category == c }.count
        case .app(let bundleID):
            return defaultCountByBundleID[bundleID, default: 0]
        }
    }

    /// Other extensions that share this entry's UTI, and therefore move with it.
    ///
    /// macOS stores defaults per UTI, not per extension: `.jpg` and `.jpeg` are
    /// both `public.jpeg`, so changing one changes both. There is no system
    /// reverse-lookup from UTI to extensions, so this scans `entries` — one pass
    /// over data already in memory.
    ///
    /// Always empty for URL schemes: each scheme is its own key.
    func siblingExtensions(of entry: HandlerEntry) -> [String] {
        guard entry.kind == .fileExtension, let uti = entry.uti else { return [] }
        return entries
            .filter { $0.kind == .fileExtension && $0.uti == uti && $0.id != entry.id }
            .map(\.displayName)
            .sorted()
    }

    /// The entries an export of `scope` should contain.
    ///
    /// `.visible` deliberately reuses `filteredEntries`, so the sidebar filter
    /// and the search box mean the same thing in the file as on screen. Row
    /// order is the exporter's business, not this method's.
    func entriesForExport(scope: ExportScope) -> [HandlerEntry] {
        switch scope {
        case .visible: return filteredEntries
        case .all: return entries
        }
    }

    func setBrowseMode(_ mode: BrowseMode) {
        browseMode = mode
        selectedEntryID = nil
        switch mode {
        case .categories:
            selectedFilter = .allCategories
        case .apps:
            if let first = appsWithDefaults.first {
                selectedFilter = .app(bundleID: first.bundleID)
            } else {
                selectedFilter = .allCategories
            }
        }
    }

    /// Cold start: render the cached snapshot if there is one, then probe.
    /// Removes the blank table that otherwise sits there for the probe's ~3.6s.
    func start() async {
        if entries.isEmpty {
            let directory = snapshotDirectory
            // Decoding ~900 KB costs tens of milliseconds — cheap, but free to
            // keep off the main actor at launch.
            if let snapshot = await Task.detached(priority: .userInitiated, operation: {
                SnapshotStore.load(baseDirectory: directory)
            }).value {
                entries = snapshot.entries
                cacheCapturedAt = snapshot.capturedAt
            }
        }
        await refresh()
    }

    /// Probe and swap. Used by `start()` and by the Refresh toolbar button.
    func refresh() async {
        // Reject an overlapping refresh rather than racing it: the loser's stale
        // result would otherwise land after the winner's and overwrite it. The
        // same applies to a change awaiting the user's answer in the OS dialog.
        guard !isLoading, pendingChangeEntryID == nil else { return }

        isLoading = true
        failureReason = nil
        // A refresh supersedes the last change: leaving the message up puts a
        // stale error under a row this probe is about to correct.
        lastChangeOutcome = nil
        defer { isLoading = false }

        let result = await probe()

        if let reason = result.failureReason {
            failureReason = reason
            // Deliberately does NOT touch `entries`: a failed probe must never
            // clobber good data that is already on screen. `cacheCapturedAt` is
            // left as-is so the banner can still say how old those rows are.
            return
        }

        entries = result.entries
        cacheCapturedAt = nil           // showing live data now
        reconcileSelection()

        // Synchronous on purpose: a detached save here races any test (or any
        // caller) that reads the file back right after `refresh()` returns.
        // Measured ~11 ms (10 ms encode + 0.5 ms atomic write) for ~1,500
        // entries — comfortably under one 60 Hz frame. Don't move this back
        // into a detached task without re-solving that race.
        SnapshotStore.save(result.entries, baseDirectory: snapshotDirectory)
    }

    /// Ask the system to make `app` the default for `entry`.
    ///
    /// macOS shows its own confirmation dialog and blocks until the user
    /// answers, so this can take an unbounded amount of time. Only `.applied`
    /// touches `entries` or the snapshot — a declined change changed nothing,
    /// so there is nothing to write.
    func changeDefault(to app: AppRef, for entry: HandlerEntry) async {
        // Don't race a probe: its result would overwrite the splice below.
        guard !isLoading, pendingChangeEntryID == nil else { return }

        // The caller's copy can be older than the row on screen: a refresh
        // landing between render and click leaves the view holding a
        // snapshot-era entry. Resolve the live row and use it for both the write
        // and the sibling scan — a stale `uti` would otherwise bind the default
        // to the wrong content type, and find none of the real siblings.
        let live = entries.first { $0.id == entry.id } ?? entry

        pendingChangeEntryID = live.id
        lastChangeOutcome = nil
        defer { pendingChangeEntryID = nil }

        let outcome = await writer.setDefault(app: app, for: live)
        lastChangeOutcome = outcome

        guard case .applied = outcome else { return }

        // Every entry sharing this UTI moved, not just the one clicked.
        let affectedIDs = Set([live.id] + siblingExtensions(of: live).map { "ext:\($0)" })
        let updated = entries.map { affectedIDs.contains($0.id) ? reresolve($0) : $0 }

        // Nothing moved — the target wasn't in `entries` at all, or re-resolution
        // returned what was already there. Skip the ~11 ms re-encode of data
        // identical to what is already on disk.
        guard updated != entries else { return }
        entries = updated

        // Same reason `refresh()` calls it: this mutation can leave the Apps-mode
        // filter pointing at an app that no longer owns any entry, which blanks
        // the table. The splice preserves every id, so only the filter can strand.
        reconcileSelection()

        // Keep the cache honest: it must never claim a default the system no
        // longer reports.
        SnapshotStore.save(entries, baseDirectory: snapshotDirectory)
    }

    /// A swap can strand a selection that pointed at something no longer present —
    /// precisely what a weeks-old cache produces.
    private func reconcileSelection() {
        if let id = selectedEntryID, !entries.contains(where: { $0.id == id }) {
            selectedEntryID = nil
        }
        if case .app(let bundleID) = selectedFilter,
           !appsWithDefaults.contains(where: { $0.bundleID == bundleID }) {
            // Mirrors setBrowseMode(.apps): first available app, else All.
            selectedFilter = appsWithDefaults.first.map { .app(bundleID: $0.bundleID) }
                ?? .allCategories
        }
    }

    private func rebuildAppCache() {
        var counts: [String: Int] = [:]
        var byBundleID: [String: AppRef] = [:]
        for entry in entries {
            guard let app = entry.defaultApp, app.exists else { continue }
            counts[app.bundleID, default: 0] += 1
            if byBundleID[app.bundleID] == nil {
                byBundleID[app.bundleID] = app
            }
        }
        defaultCountByBundleID = counts
        dedupedDefaultApps = Array(byBundleID.values)
    }
}
