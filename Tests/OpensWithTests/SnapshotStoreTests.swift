import XCTest
@testable import OpensWith

final class SnapshotStoreTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpensWithTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    private func sampleEntries() -> [HandlerEntry] {
        [
            HandlerEntry(
                id: "ext:.pdf", displayName: ".pdf", kind: .fileExtension,
                uti: "com.adobe.pdf",
                defaultApp: AppRef(bundleID: "com.apple.Preview", displayName: "Preview",
                                   bundleURL: nil, exists: true),
                alternativeApps: [], category: .documents
            )
        ]
    }

    func test_saveThenLoadRoundTripsThroughARealFile() {
        let captured = Date(timeIntervalSince1970: 1_759_395_272)
        SnapshotStore.save(sampleEntries(), capturedAt: captured, baseDirectory: tempDirectory)

        let loaded = SnapshotStore.load(baseDirectory: tempDirectory)

        XCTAssertEqual(loaded?.entries, sampleEntries())
        XCTAssertEqual(loaded?.capturedAt, captured)
    }

    func test_saveCreatesIntermediateDirectories() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))

        SnapshotStore.save(sampleEntries(), capturedAt: Date(), baseDirectory: tempDirectory)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: SnapshotStore.cacheFileURL(baseDirectory: tempDirectory).path
            )
        )
    }

    func test_loadFromAnEmptyDirectoryReturnsNil() {
        XCTAssertNil(SnapshotStore.load(baseDirectory: tempDirectory))
    }

    func test_loadFromACorruptFileReturnsNilAndLeavesTheFileInPlace() throws {
        let fileURL = SnapshotStore.cacheFileURL(baseDirectory: tempDirectory)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: fileURL)

        XCTAssertNil(SnapshotStore.load(baseDirectory: tempDirectory))
        // Left in place deliberately: the next successful probe overwrites it,
        // and deleting would add a failure mode for no gain.
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func test_loadFromAFutureSchemaVersionReturnsNilAndLeavesTheFileInPlace() throws {
        let fileURL = SnapshotStore.cacheFileURL(baseDirectory: tempDirectory)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let json = #"{"schemaVersion":99,"capturedAt":"2026-10-02T08:54:32Z","entries":[]}"#
        try Data(json.utf8).write(to: fileURL)

        XCTAssertNil(SnapshotStore.load(baseDirectory: tempDirectory))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    /// An empty scan is never a legitimate result, so it must never poison the
    /// cache — a later failed probe would otherwise be stuck showing nothing.
    func test_saveRefusesToWriteAnEmptyScan() {
        SnapshotStore.save([], capturedAt: Date(), baseDirectory: tempDirectory)

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: SnapshotStore.cacheFileURL(baseDirectory: tempDirectory).path
            )
        )
    }

    func test_saveOverwritesAPreviousSnapshot() {
        let older = Date(timeIntervalSince1970: 1_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000)

        SnapshotStore.save(sampleEntries(), capturedAt: older, baseDirectory: tempDirectory)
        SnapshotStore.save(sampleEntries(), capturedAt: newer, baseDirectory: tempDirectory)

        XCTAssertEqual(SnapshotStore.load(baseDirectory: tempDirectory)?.capturedAt, newer)
    }

    /// Review Focus #5 — an unwritable destination must not crash or throw.
    /// `/dev/null` cannot contain a directory, so creating one under it fails.
    func test_saveToAnUnwritableLocationFailsSilently() {
        let unwritable = URL(fileURLWithPath: "/dev/null/OpensWith")

        SnapshotStore.save(sampleEntries(), capturedAt: Date(), baseDirectory: unwritable)

        XCTAssertNil(SnapshotStore.load(baseDirectory: unwritable))
    }

    func test_defaultBaseDirectoryIsNamedLiterallyUnderApplicationSupport() {
        let path = SnapshotStore.defaultBaseDirectory.path
        XCTAssertTrue(path.hasSuffix("/Application Support/OpensWith"), path)
    }

    func test_cacheFileLivesInACacheSubdirectory() {
        let url = SnapshotStore.cacheFileURL(baseDirectory: tempDirectory)
        XCTAssertEqual(url.lastPathComponent, "latest.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "cache")
    }
}
