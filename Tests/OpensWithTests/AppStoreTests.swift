import XCTest
@testable import OpensWith

@MainActor
final class AppStoreTests: XCTestCase {
    private func makeEntry(_ ext: String, app: String, category: OpensWith.Category) -> HandlerEntry {
        HandlerEntry(
            id: "ext:\(ext)", displayName: ext, kind: .fileExtension,
            uti: nil,
            defaultApp: AppRef(bundleID: app, displayName: app, bundleURL: nil, exists: true),
            alternativeApps: [], category: category
        )
    }

    func test_allCategoriesShowsEveryEntry() {
        let store = AppStore()
        store.entries = [
            makeEntry(".pdf", app: "Preview", category: .documents),
            makeEntry(".png", app: "Preview", category: .images),
        ]
        store.selectedFilter = .allCategories
        XCTAssertEqual(store.filteredEntries.count, 2)
    }

    func test_categoryFilterNarrowsEntries() {
        let store = AppStore()
        store.entries = [
            makeEntry(".pdf", app: "Preview", category: .documents),
            makeEntry(".png", app: "Preview", category: .images),
        ]
        store.selectedFilter = .category(.images)
        XCTAssertEqual(store.filteredEntries.map(\.displayName), [".png"])
    }

    func test_searchMatchesExtensionOrAppName_caseInsensitive() {
        let store = AppStore()
        store.entries = [
            makeEntry(".md", app: "Xcode", category: .codeText),
            makeEntry(".pdf", app: "Preview", category: .documents),
        ]
        store.selectedFilter = .allCategories

        store.searchText = "xcode"
        XCTAssertEqual(store.filteredEntries.map(\.displayName), [".md"])

        store.searchText = "PDF"
        XCTAssertEqual(store.filteredEntries.map(\.displayName), [".pdf"])
    }

    func test_categoryCountsExcludeSearchFilter() {
        let store = AppStore()
        store.entries = [
            makeEntry(".pdf", app: "Preview", category: .documents),
            makeEntry(".png", app: "Preview", category: .images),
            makeEntry(".jpg", app: "Preview", category: .images),
        ]
        XCTAssertEqual(store.count(for: .category(.images)), 2)
        XCTAssertEqual(store.count(for: .allCategories), 3)
    }

    func test_appFilter_returnsOnlyEntriesOwnedByThatApp() {
        let store = AppStore()
        store.entries = [
            makeEntry(".pdf", app: "com.apple.Preview", category: .documents),
            makeEntry(".png", app: "com.apple.Preview", category: .images),
            makeEntry(".html", app: "com.brave.Browser", category: .codeText),
        ]
        store.selectedFilter = .app(bundleID: "com.apple.Preview")
        XCTAssertEqual(
            store.filteredEntries.map(\.displayName).sorted(),
            [".pdf", ".png"]
        )
    }

    func test_appFilter_plusSearchNarrowsByExtension() {
        let store = AppStore()
        store.entries = [
            makeEntry(".pdf", app: "com.apple.Preview", category: .documents),
            makeEntry(".png", app: "com.apple.Preview", category: .images),
        ]
        store.selectedFilter = .app(bundleID: "com.apple.Preview")
        store.searchText = "pdf"
        XCTAssertEqual(store.filteredEntries.map(\.displayName), [".pdf"])
    }

    func test_countForAppFilter_matchesOwnership() {
        let store = AppStore()
        store.entries = [
            makeEntry(".pdf", app: "com.apple.Preview", category: .documents),
            makeEntry(".png", app: "com.apple.Preview", category: .images),
            makeEntry(".html", app: "com.brave.Browser", category: .codeText),
        ]
        XCTAssertEqual(store.count(for: .app(bundleID: "com.apple.Preview")), 2)
        XCTAssertEqual(store.count(for: .app(bundleID: "com.brave.Browser")), 1)
        XCTAssertEqual(store.count(for: .app(bundleID: "nonexistent")), 0)
    }

    private func makeEntryWithApp(_ ext: String, bundleID: String, displayName: String, exists: Bool = true, category: OpensWith.Category = .other) -> HandlerEntry {
        HandlerEntry(
            id: "ext:\(ext)", displayName: ext, kind: .fileExtension,
            uti: nil,
            defaultApp: AppRef(bundleID: bundleID, displayName: displayName, bundleURL: nil, exists: exists),
            alternativeApps: [], category: category
        )
    }

    func test_appsWithDefaults_dedupesByBundleID() {
        let store = AppStore()
        store.entries = [
            makeEntryWithApp(".pdf", bundleID: "com.apple.Preview", displayName: "Preview"),
            makeEntryWithApp(".png", bundleID: "com.apple.Preview", displayName: "Preview"),
            makeEntryWithApp(".html", bundleID: "com.brave.Browser", displayName: "Brave"),
        ]
        let apps = store.appsWithDefaults
        XCTAssertEqual(apps.map(\.bundleID).sorted(), ["com.apple.Preview", "com.brave.Browser"])
    }

    func test_appsWithDefaults_excludesAppsThatDoNotExist() {
        let store = AppStore()
        store.entries = [
            makeEntryWithApp(".pdf", bundleID: "com.apple.Preview", displayName: "Preview", exists: true),
            makeEntryWithApp(".ghost", bundleID: "com.dead.App", displayName: "Ghost", exists: false),
        ]
        let apps = store.appsWithDefaults
        XCTAssertEqual(apps.map(\.bundleID), ["com.apple.Preview"])
    }

    func test_appsWithDefaults_excludesEntriesWithNoDefaultApp() {
        let store = AppStore()
        let withApp = makeEntryWithApp(".pdf", bundleID: "com.apple.Preview", displayName: "Preview")
        let withoutApp = HandlerEntry(
            id: "ext:.unknown", displayName: ".unknown", kind: .fileExtension,
            uti: nil,
            defaultApp: nil, alternativeApps: [], category: .other
        )
        store.entries = [withApp, withoutApp]
        XCTAssertEqual(store.appsWithDefaults.map(\.bundleID), ["com.apple.Preview"])
    }

    func test_appsWithDefaults_sortByNameAscending() {
        let store = AppStore()
        store.entries = [
            makeEntryWithApp(".html", bundleID: "b", displayName: "Brave"),
            makeEntryWithApp(".pdf", bundleID: "a", displayName: "Acrobat"),
            makeEntryWithApp(".png", bundleID: "p", displayName: "Preview"),
        ]
        store.appSortKey = .name
        store.appSortDirection = .ascending
        XCTAssertEqual(store.appsWithDefaults.map(\.displayName), ["Acrobat", "Brave", "Preview"])
    }

    func test_appsWithDefaults_sortByNameDescending() {
        let store = AppStore()
        store.entries = [
            makeEntryWithApp(".html", bundleID: "b", displayName: "Brave"),
            makeEntryWithApp(".pdf", bundleID: "a", displayName: "Acrobat"),
            makeEntryWithApp(".png", bundleID: "p", displayName: "Preview"),
        ]
        store.appSortKey = .name
        store.appSortDirection = .descending
        XCTAssertEqual(store.appsWithDefaults.map(\.displayName), ["Preview", "Brave", "Acrobat"])
    }

    func test_appsWithDefaults_sortByCountDescending() {
        let store = AppStore()
        store.entries = [
            makeEntryWithApp(".html", bundleID: "b", displayName: "Brave"),
            makeEntryWithApp(".pdf", bundleID: "p", displayName: "Preview"),
            makeEntryWithApp(".png", bundleID: "p", displayName: "Preview"),
            makeEntryWithApp(".jpg", bundleID: "p", displayName: "Preview"),
        ]
        store.appSortKey = .count
        store.appSortDirection = .descending
        XCTAssertEqual(store.appsWithDefaults.map(\.displayName), ["Preview", "Brave"])
    }

    func test_appsWithDefaults_sortByCountAscending() {
        let store = AppStore()
        store.entries = [
            makeEntryWithApp(".html", bundleID: "b", displayName: "Brave"),
            makeEntryWithApp(".pdf", bundleID: "p", displayName: "Preview"),
            makeEntryWithApp(".png", bundleID: "p", displayName: "Preview"),
        ]
        store.appSortKey = .count
        store.appSortDirection = .ascending
        XCTAssertEqual(store.appsWithDefaults.map(\.displayName), ["Brave", "Preview"])
    }

    func test_appsWithDefaults_sortByCountTieBreaksByNameAscending() {
        let store = AppStore()
        store.entries = [
            makeEntryWithApp(".html", bundleID: "z", displayName: "Zebra"),
            makeEntryWithApp(".pdf", bundleID: "a", displayName: "Acrobat"),
            makeEntryWithApp(".png", bundleID: "m", displayName: "Mango"),
        ]
        store.appSortKey = .count
        store.appSortDirection = .descending
        // All three have count 1 — tie-break should be name ascending regardless of primary direction.
        XCTAssertEqual(store.appsWithDefaults.map(\.displayName), ["Acrobat", "Mango", "Zebra"])
    }

    func test_appsWithDefaults_emptyEntriesReturnsEmpty() {
        let store = AppStore()
        store.entries = []
        XCTAssertTrue(store.appsWithDefaults.isEmpty)
    }

    func test_setBrowseModeApps_selectsFirstAppAndClearsEntrySelection() {
        let store = AppStore()
        store.entries = [
            makeEntryWithApp(".pdf", bundleID: "a", displayName: "Acrobat"),
            makeEntryWithApp(".html", bundleID: "b", displayName: "Brave"),
        ]
        store.appSortKey = .name
        store.appSortDirection = .ascending
        store.selectedEntryID = "ext:.pdf"

        store.setBrowseMode(.apps)

        XCTAssertEqual(store.browseMode, .apps)
        XCTAssertEqual(store.selectedFilter, .app(bundleID: "a"))
        XCTAssertNil(store.selectedEntryID)
    }

    func test_setBrowseModeCategories_resetsToAllAndClearsEntrySelection() {
        let store = AppStore()
        store.entries = [
            makeEntryWithApp(".pdf", bundleID: "a", displayName: "Acrobat"),
        ]
        store.browseMode = .apps
        store.selectedFilter = .app(bundleID: "a")
        store.selectedEntryID = "ext:.pdf"

        store.setBrowseMode(.categories)

        XCTAssertEqual(store.browseMode, .categories)
        XCTAssertEqual(store.selectedFilter, .allCategories)
        XCTAssertNil(store.selectedEntryID)
    }

    func test_setBrowseModeApps_emptyStore_fallsBackToAllCategories() {
        let store = AppStore()
        store.entries = []
        store.selectedEntryID = "anything"

        store.setBrowseMode(.apps)

        XCTAssertEqual(store.browseMode, .apps)
        XCTAssertEqual(store.selectedFilter, .allCategories)
        XCTAssertNil(store.selectedEntryID)
    }

    // MARK: - Export scope

    func test_exportScopeAll_ignoresFilterAndSearch() {
        let store = AppStore()
        store.entries = [
            makeEntry(".pdf", app: "Preview", category: .documents),
            makeEntry(".png", app: "Preview", category: .images),
        ]
        store.selectedFilter = .category(.images)
        store.searchText = "png"

        XCTAssertEqual(store.entriesForExport(scope: .all).map(\.displayName).sorted(),
                       [".pdf", ".png"])
    }

    func test_exportScopeVisible_honoursTheCategoryFilter() {
        let store = AppStore()
        store.entries = [
            makeEntry(".pdf", app: "Preview", category: .documents),
            makeEntry(".png", app: "Preview", category: .images),
        ]
        store.selectedFilter = .category(.images)

        XCTAssertEqual(store.entriesForExport(scope: .visible).map(\.displayName), [".png"])
    }

    func test_exportScopeVisible_honoursSearchOnTopOfTheFilter() {
        let store = AppStore()
        store.entries = [
            makeEntry(".png", app: "Preview", category: .images),
            makeEntry(".jpg", app: "Preview", category: .images),
        ]
        store.selectedFilter = .category(.images)
        store.searchText = "jpg"

        XCTAssertEqual(store.entriesForExport(scope: .visible).map(\.displayName), [".jpg"])
    }

    func test_exportScopeVisible_honoursTheAppFilter() {
        let store = AppStore()
        store.entries = [
            makeEntryWithApp(".pdf", bundleID: "com.apple.Preview", displayName: "Preview"),
            makeEntryWithApp(".html", bundleID: "com.brave.Browser", displayName: "Brave"),
        ]
        store.selectedFilter = .app(bundleID: "com.brave.Browser")

        XCTAssertEqual(store.entriesForExport(scope: .visible).map(\.displayName), [".html"])
    }

    // MARK: - Persistence & refresh

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OpensWithTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func succeedingProbe(_ entries: [HandlerEntry]) -> () async -> ProbeResult {
        { ProbeResult(entries: entries, failureReason: nil) }
    }

    private func failingProbe(_ reason: String) -> () async -> ProbeResult {
        { ProbeResult(entries: [], failureReason: reason) }
    }

    func test_refreshSuccess_replacesEntriesAndClearsCacheTimestamp() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let fresh = [makeEntry(".png", app: "Preview", category: .images)]
        let store = AppStore(probe: succeedingProbe(fresh), snapshotDirectory: temp)
        store.cacheCapturedAt = Date()

        await store.refresh()

        XCTAssertEqual(store.entries.map(\.displayName), [".png"])
        XCTAssertNil(store.cacheCapturedAt)
        XCTAssertNil(store.failureReason)
        XCTAssertFalse(store.isLoading)
    }

    /// The core invariant of this feature: good data already on screen survives
    /// a failed probe. Before this change, a failed refresh emptied the table.
    func test_refreshFailure_leavesExistingEntriesUntouched() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = AppStore(probe: failingProbe("lsregister exploded"), snapshotDirectory: temp)
        store.entries = [makeEntry(".pdf", app: "Preview", category: .documents)]
        let cachedAt = Date(timeIntervalSince1970: 1_759_395_272)
        store.cacheCapturedAt = cachedAt

        await store.refresh()

        XCTAssertEqual(store.entries.map(\.displayName), [".pdf"])
        XCTAssertEqual(store.failureReason, "lsregister exploded")
        XCTAssertEqual(store.cacheCapturedAt, cachedAt)
        XCTAssertEqual(store.bannerState, .failedShowingCache(since: cachedAt))
    }

    func test_refreshFailure_withNoEntries_behavesAsBefore() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = AppStore(probe: failingProbe("nope"), snapshotDirectory: temp)

        await store.refresh()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.failureReason, "nope")
        XCTAssertEqual(store.bannerState, .failed(reason: "nope"))
    }

    func test_refreshSuccess_writesTheSnapshotToDisk() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let fresh = [makeEntry(".png", app: "Preview", category: .images)]
        let store = AppStore(probe: succeedingProbe(fresh), snapshotDirectory: temp)

        await store.refresh()

        XCTAssertEqual(SnapshotStore.load(baseDirectory: temp)?.entries.map(\.displayName), [".png"])
    }

    func test_refreshFailure_doesNotWriteASnapshot() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = AppStore(probe: failingProbe("nope"), snapshotDirectory: temp)

        await store.refresh()

        XCTAssertNil(SnapshotStore.load(baseDirectory: temp))
    }

    func test_start_rendersTheCachedSnapshotBeforeProbing() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let cached = [makeEntry(".pdf", app: "Preview", category: .documents)]
        let capturedAt = Date(timeIntervalSince1970: 1_759_395_272)
        SnapshotStore.save(cached, capturedAt: capturedAt, baseDirectory: temp)

        // A probe that fails, so the cached rows are what remains at the end and
        // we can assert they were rendered at all.
        let store = AppStore(probe: failingProbe("offline"), snapshotDirectory: temp)

        await store.start()

        XCTAssertEqual(store.entries.map(\.displayName), [".pdf"])
        XCTAssertEqual(store.cacheCapturedAt, capturedAt)
        XCTAssertEqual(store.bannerState, .failedShowingCache(since: capturedAt))
    }

    func test_start_withNoCache_behavesAsBefore() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let fresh = [makeEntry(".png", app: "Preview", category: .images)]
        let store = AppStore(probe: succeedingProbe(fresh), snapshotDirectory: temp)

        await store.start()

        XCTAssertNil(store.cacheCapturedAt)
        XCTAssertEqual(store.entries.map(\.displayName), [".png"])
        XCTAssertEqual(store.bannerState, .hidden)
    }

    func test_start_cacheIsSupersededByASuccessfulProbe() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        SnapshotStore.save([makeEntry(".pdf", app: "Preview", category: .documents)],
                           capturedAt: Date(timeIntervalSince1970: 1_000_000),
                           baseDirectory: temp)

        let fresh = [makeEntry(".png", app: "Preview", category: .images)]
        let store = AppStore(probe: succeedingProbe(fresh), snapshotDirectory: temp)

        await store.start()

        XCTAssertEqual(store.entries.map(\.displayName), [".png"])
        XCTAssertNil(store.cacheCapturedAt)
        XCTAssertEqual(store.bannerState, .hidden)
    }

    /// Review Focus #3 — Refresh clicked while the startup probe is in flight.
    /// The second call must return immediately rather than racing, so a slow
    /// stale probe cannot overwrite a fresher result.
    func test_refresh_whileAlreadyLoading_returnsImmediately() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = AppStore(probe: succeedingProbe([]), snapshotDirectory: temp)
        store.entries = [makeEntry(".pdf", app: "Preview", category: .documents)]
        store.isLoading = true

        await store.refresh()

        // Untouched: the guard returned before the probe ran.
        XCTAssertEqual(store.entries.map(\.displayName), [".pdf"])
        XCTAssertTrue(store.isLoading)
    }

    func test_swap_clearsASelectionPointingAtAVanishedEntry() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let fresh = [makeEntry(".png", app: "Preview", category: .images)]
        let store = AppStore(probe: succeedingProbe(fresh), snapshotDirectory: temp)
        store.entries = [makeEntry(".pdf", app: "Preview", category: .documents)]
        store.selectedEntryID = "ext:.pdf"

        await store.refresh()

        XCTAssertNil(store.selectedEntryID)
    }

    func test_swap_keepsASelectionThatStillExists() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let fresh = [
            makeEntry(".pdf", app: "Preview", category: .documents),
            makeEntry(".png", app: "Preview", category: .images),
        ]
        let store = AppStore(probe: succeedingProbe(fresh), snapshotDirectory: temp)
        store.entries = [makeEntry(".pdf", app: "Preview", category: .documents)]
        store.selectedEntryID = "ext:.pdf"

        await store.refresh()

        XCTAssertEqual(store.selectedEntryID, "ext:.pdf")
    }

    func test_swap_appFilterForAVanishedApp_fallsBackToTheFirstApp() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let fresh = [makeEntryWithApp(".png", bundleID: "com.apple.Preview", displayName: "Preview")]
        let store = AppStore(probe: succeedingProbe(fresh), snapshotDirectory: temp)
        store.entries = [makeEntryWithApp(".html", bundleID: "com.gone.App", displayName: "Gone")]
        store.browseMode = .apps
        store.selectedFilter = .app(bundleID: "com.gone.App")

        await store.refresh()

        XCTAssertEqual(store.selectedFilter, .app(bundleID: "com.apple.Preview"))
    }

    func test_swap_appFilterWithNoAppsRemaining_fallsBackToAllCategories() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let orphan = HandlerEntry(
            id: "ext:.x", displayName: ".x", kind: .fileExtension, uti: nil,
            defaultApp: nil, alternativeApps: [], category: .other
        )
        let store = AppStore(probe: succeedingProbe([orphan]), snapshotDirectory: temp)
        store.entries = [makeEntryWithApp(".html", bundleID: "com.gone.App", displayName: "Gone")]
        store.browseMode = .apps
        store.selectedFilter = .app(bundleID: "com.gone.App")

        await store.refresh()

        XCTAssertEqual(store.selectedFilter, .allCategories)
    }

    func test_swap_leavesACategoryFilterAlone() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let fresh = [makeEntry(".png", app: "Preview", category: .images)]
        let store = AppStore(probe: succeedingProbe(fresh), snapshotDirectory: temp)
        store.selectedFilter = .category(.images)

        await store.refresh()

        XCTAssertEqual(store.selectedFilter, .category(.images))
    }
}
