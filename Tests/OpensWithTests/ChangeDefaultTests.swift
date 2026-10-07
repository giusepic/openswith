import XCTest
@testable import OpensWith

@MainActor
final class ChangeDefaultTests: XCTestCase {

    private func makeApp(_ bundleID: String, displayName: String? = nil) -> AppRef {
        AppRef(bundleID: bundleID,
               displayName: displayName ?? bundleID,
               bundleURL: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
               exists: true)
    }

    private func entry(_ ext: String,
                       uti: String?,
                       app: String,
                       category: OpensWith.Category = .images) -> HandlerEntry {
        HandlerEntry(id: "ext:\(ext)", displayName: ext, kind: .fileExtension,
                     uti: uti, defaultApp: makeApp(app),
                     alternativeApps: [makeApp("com.google.Chrome")],
                     category: category)
    }

    private func schemeEntry(_ scheme: String, app: String) -> HandlerEntry {
        HandlerEntry(id: "url:\(scheme)", displayName: "\(scheme):", kind: .urlScheme,
                     uti: nil, defaultApp: makeApp(app),
                     alternativeApps: [makeApp("com.google.Chrome")],
                     category: .urlSchemes)
    }

    func test_siblingExtensions_findsEntriesSharingAUTI() {
        let store = AppStore()
        store.entries = [
            entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview"),
            entry(".jpeg", uti: "public.jpeg", app: "com.apple.Preview"),
            entry(".png", uti: "public.png", app: "com.apple.Preview"),
        ]

        let siblings = store.siblingExtensions(of: store.entries[0])

        XCTAssertEqual(siblings, [".jpeg"])
    }

    func test_siblingExtensions_uniqueUTIHasNone() {
        let store = AppStore()
        store.entries = [
            entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview"),
            entry(".png", uti: "public.png", app: "com.apple.Preview"),
        ]

        XCTAssertEqual(store.siblingExtensions(of: store.entries[1]), [])
    }

    func test_siblingExtensions_nilUTIHasNone() {
        let store = AppStore()
        store.entries = [
            entry(".weird", uti: nil, app: "com.apple.Preview"),
            entry(".alsoweird", uti: nil, app: "com.apple.Preview"),
        ]

        // Two nil UTIs are not siblings of each other — nil means "unresolved",
        // not "the same type".
        XCTAssertEqual(store.siblingExtensions(of: store.entries[0]), [])
    }

    func test_siblingExtensions_urlSchemeHasNone() {
        let store = AppStore()
        store.entries = [
            schemeEntry("mailto", app: "com.apple.mail"),
            schemeEntry("mailto2", app: "com.apple.mail"),
        ]

        XCTAssertEqual(store.siblingExtensions(of: store.entries[0]), [])
    }

    func test_siblingExtensions_sortedAndExcludesSelf() {
        let store = AppStore()
        store.entries = [
            entry(".tiff", uti: "public.tiff", app: "com.apple.Preview"),
            entry(".tif", uti: "public.tiff", app: "com.apple.Preview"),
            entry(".tiff2", uti: "public.tiff", app: "com.apple.Preview"),
        ]

        XCTAssertEqual(store.siblingExtensions(of: store.entries[0]), [".tif", ".tiff2"])
    }

    // MARK: - changeDefault

    private final class StubWriter: DefaultsWriting, @unchecked Sendable {
        var outcome: ChangeOutcome
        private(set) var callCount = 0

        init(outcome: ChangeOutcome) { self.outcome = outcome }

        func setDefault(app: AppRef, for entry: HandlerEntry) async -> ChangeOutcome {
            callCount += 1
            return outcome
        }
    }

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OpensWithTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// Re-resolution hits the live system, so it is injected: these tests must
    /// not depend on what is installed on the machine running them.
    private func stubReresolve(to app: AppRef) -> (HandlerEntry) -> HandlerEntry {
        { entry in
            HandlerEntry(id: entry.id, displayName: entry.displayName, kind: entry.kind,
                         uti: entry.uti, defaultApp: app,
                         alternativeApps: entry.alternativeApps, category: entry.category)
        }
    }

    func test_applied_updatesTheChangedEntry() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let chrome = makeApp("com.google.Chrome")
        let store = AppStore(snapshotDirectory: temp,
                             writer: StubWriter(outcome: .applied(chrome)),
                             reresolve: stubReresolve(to: chrome))
        store.entries = [entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview")]

        await store.changeDefault(to: chrome, for: store.entries[0])

        XCTAssertEqual(store.entries[0].defaultApp?.bundleID, "com.google.Chrome")
        XCTAssertEqual(store.lastChangeOutcome, .applied(chrome))
    }

    func test_applied_updatesEverySiblingSharingTheUTI() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let chrome = makeApp("com.google.Chrome")
        let store = AppStore(snapshotDirectory: temp,
                             writer: StubWriter(outcome: .applied(chrome)),
                             reresolve: stubReresolve(to: chrome))
        store.entries = [
            entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview"),
            entry(".jpeg", uti: "public.jpeg", app: "com.apple.Preview"),
            entry(".png", uti: "public.png", app: "com.apple.Preview"),
        ]

        await store.changeDefault(to: chrome, for: store.entries[0])

        XCTAssertEqual(store.entries[0].defaultApp?.bundleID, "com.google.Chrome")
        XCTAssertEqual(store.entries[1].defaultApp?.bundleID, "com.google.Chrome",
                       ".jpeg shares public.jpeg and must move with .jpg")
        XCTAssertEqual(store.entries[2].defaultApp?.bundleID, "com.apple.Preview",
                       ".png has its own UTI and must not move")
    }

    /// The caller's copy can be older than the row on screen — a refresh landing
    /// between render and click leaves the view holding a snapshot-era entry.
    /// Siblings resolved from that stale UTI find nothing, so `.jpeg` silently
    /// keeps pointing at the old app while `.jpg` moves.
    func test_applied_resolvesSiblingsFromTheLiveRowNotTheCallersCopy() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let chrome = makeApp("com.google.Chrome")
        let store = AppStore(snapshotDirectory: temp,
                             writer: StubWriter(outcome: .applied(chrome)),
                             reresolve: stubReresolve(to: chrome))
        store.entries = [
            entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview"),
            entry(".jpeg", uti: "public.jpeg", app: "com.apple.Preview"),
        ]

        // Same id, stale UTI — exactly what a snapshot-era copy looks like.
        let stale = entry(".jpg", uti: "com.stale.jpeg", app: "com.apple.Preview")
        await store.changeDefault(to: chrome, for: stale)

        XCTAssertEqual(store.entries[0].defaultApp?.bundleID, "com.google.Chrome")
        XCTAssertEqual(store.entries[1].defaultApp?.bundleID, "com.google.Chrome",
                       ".jpeg was left behind: siblings resolved from the stale UTI")
    }

    func test_changeDefault_whileLoading_isRejected() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let chrome = makeApp("com.google.Chrome")
        let writer = StubWriter(outcome: .applied(chrome))
        let store = AppStore(snapshotDirectory: temp, writer: writer,
                             reresolve: stubReresolve(to: chrome))
        store.entries = [entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview")]
        store.isLoading = true

        await store.changeDefault(to: chrome, for: store.entries[0])

        XCTAssertEqual(writer.callCount, 0)
        XCTAssertEqual(store.entries[0].defaultApp?.bundleID, "com.apple.Preview")
    }

    func test_refresh_whileAChangeIsPending_isRejected() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let fresh = [entry(".png", uti: "public.png", app: "com.apple.Preview")]
        let store = AppStore(probe: { ProbeResult(entries: fresh, failureReason: nil) },
                             snapshotDirectory: temp)
        store.entries = [entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview")]
        store.pendingChangeEntryID = "ext:.jpg"

        await store.refresh()

        // Untouched: the guard returned before the probe ran.
        XCTAssertEqual(store.entries.map(\.displayName), [".jpg"])
    }

    func test_declined_changesNothingAndWritesNoSnapshot() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let chrome = makeApp("com.google.Chrome")
        let store = AppStore(snapshotDirectory: temp,
                             writer: StubWriter(outcome: .declined),
                             reresolve: stubReresolve(to: chrome))
        let original = entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview")
        store.entries = [original]

        await store.changeDefault(to: chrome, for: original)

        XCTAssertEqual(store.entries, [original])
        XCTAssertEqual(store.lastChangeOutcome, .declined)
        XCTAssertNil(SnapshotStore.load(baseDirectory: temp),
                     "a declined change must not rewrite the cache")
    }

    func test_refused_changesNothingButRecordsTheOutcome() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let chrome = makeApp("com.google.Chrome")
        let store = AppStore(snapshotDirectory: temp,
                             writer: StubWriter(outcome: .refused),
                             reresolve: stubReresolve(to: chrome))
        let original = entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview")
        store.entries = [original]

        await store.changeDefault(to: chrome, for: original)

        XCTAssertEqual(store.entries, [original])
        XCTAssertEqual(store.lastChangeOutcome, .refused)
    }

    func test_failed_recordsTheReason() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let chrome = makeApp("com.google.Chrome")
        let store = AppStore(snapshotDirectory: temp,
                             writer: StubWriter(outcome: .failed(reason: "boom")),
                             reresolve: stubReresolve(to: chrome))
        store.entries = [entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview")]

        await store.changeDefault(to: chrome, for: store.entries[0])

        XCTAssertEqual(store.lastChangeOutcome, .failed(reason: "boom"))
    }

    /// Left set, this disables Refresh for the rest of the session.
    func test_pendingIsClearedOnEveryOutcome() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let chrome = makeApp("com.google.Chrome")
        for outcome: ChangeOutcome in [.applied(chrome), .declined, .refused,
                                       .failed(reason: "boom")] {
            let store = AppStore(snapshotDirectory: temp,
                                 writer: StubWriter(outcome: outcome),
                                 reresolve: stubReresolve(to: chrome))
            store.entries = [entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview")]

            await store.changeDefault(to: chrome, for: store.entries[0])

            XCTAssertNil(store.pendingChangeEntryID,
                         "pendingChangeEntryID survived outcome \(outcome)")
        }
    }

    /// Same hazard `refresh()` calls `reconcileSelection()` for: a mutation can
    /// strand the Apps-mode filter on an app that no longer owns any entry,
    /// leaving the sidebar pointing at a row that isn't there and the table blank.
    func test_applied_reconcilesAStrandedAppFilter() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let chrome = makeApp("com.google.Chrome")
        let store = AppStore(snapshotDirectory: temp,
                             writer: StubWriter(outcome: .applied(chrome)),
                             reresolve: stubReresolve(to: chrome))
        // Preview is the default for exactly one entry, and the sidebar filters on it.
        store.entries = [entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview")]
        store.browseMode = .apps
        store.selectedFilter = .app(bundleID: "com.apple.Preview")

        await store.changeDefault(to: chrome, for: store.entries[0])

        // Preview now owns nothing, so the filter must move rather than strand.
        XCTAssertFalse(store.filteredEntries.isEmpty,
                       "the table went blank: filter still points at an app owning no entries")
        if case .app(let bundleID) = store.selectedFilter {
            XCTAssertEqual(bundleID, "com.google.Chrome")
        } else {
            XCTFail("expected the filter to move to a live app, got \(store.selectedFilter)")
        }
    }

    /// A refresh supersedes whatever the last change said. Leaving the message
    /// up puts a stale error under a row the refresh just corrected.
    func test_refresh_clearsTheLastChangeOutcome() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let fresh = [entry(".png", uti: "public.png", app: "com.apple.Preview")]
        let store = AppStore(probe: { ProbeResult(entries: fresh, failureReason: nil) },
                             snapshotDirectory: temp)
        store.entries = [entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview")]
        store.lastChangeOutcome = .failed(reason: "boom")

        await store.refresh()

        XCTAssertNil(store.lastChangeOutcome,
                     "a stale error survived the refresh that superseded it")
    }

    /// `DetailView`'s `onChange` lives inside its `if let entry` branch, so it
    /// cannot fire when the selection goes to nil (empty-space click,
    /// `setBrowseMode`, `reconcileSelection`). The store has to own this, or the
    /// next entry selected inherits the previous entry's banner.
    func test_deselecting_clearsTheLastChangeOutcome() {
        let store = AppStore()
        store.entries = [entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview")]
        store.selectedEntryID = "ext:.jpg"
        store.lastChangeOutcome = .applied(makeApp("com.google.Chrome"))

        store.setBrowseMode(.apps)

        XCTAssertNil(store.lastChangeOutcome,
                     "the banner outlived the selection it described")
    }

    func test_applied_writesTheSnapshot() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let chrome = makeApp("com.google.Chrome")
        let store = AppStore(snapshotDirectory: temp,
                             writer: StubWriter(outcome: .applied(chrome)),
                             reresolve: stubReresolve(to: chrome))
        store.entries = [entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview")]

        await store.changeDefault(to: chrome, for: store.entries[0])

        let saved = SnapshotStore.load(baseDirectory: temp)
        XCTAssertEqual(saved?.entries.first?.defaultApp?.bundleID, "com.google.Chrome")
    }

    /// If the target isn't in `entries`, the splice is a no-op — so writing the
    /// snapshot re-encodes ~1,500 identical entries for nothing.
    func test_applied_forAnEntryNotInTheTable_writesNoSnapshot() async {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let chrome = makeApp("com.google.Chrome")
        let store = AppStore(snapshotDirectory: temp,
                             writer: StubWriter(outcome: .applied(chrome)),
                             reresolve: stubReresolve(to: chrome))
        store.entries = [entry(".png", uti: "public.png", app: "com.apple.Preview")]

        let absent = entry(".jpg", uti: "public.jpeg", app: "com.apple.Preview")
        await store.changeDefault(to: chrome, for: absent)

        XCTAssertNil(SnapshotStore.load(baseDirectory: temp),
                     "wrote a snapshot for a change that altered nothing")
    }
}
