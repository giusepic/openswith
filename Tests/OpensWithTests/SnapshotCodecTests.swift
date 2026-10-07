import XCTest
@testable import OpensWith

final class SnapshotCodecTests: XCTestCase {

    private func sampleEntries() -> [HandlerEntry] {
        [
            HandlerEntry(
                id: "ext:.pdf",
                displayName: ".pdf",
                kind: .fileExtension,
                uti: "com.adobe.pdf",
                defaultApp: AppRef(
                    bundleID: "com.apple.Preview",
                    displayName: "Preview",
                    bundleURL: URL(fileURLWithPath: "/System/Applications/Preview.app"),
                    exists: true
                ),
                alternativeApps: [
                    AppRef(
                        bundleID: "com.google.Chrome",
                        displayName: "Google Chrome",
                        bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
                        exists: true
                    )
                ],
                category: .documents
            ),
            // No default app, no UTI, no alternatives, no bundle URL — every optional nil.
            HandlerEntry(
                id: "ext:.unknown",
                displayName: ".unknown",
                kind: .fileExtension,
                uti: nil,
                defaultApp: nil,
                alternativeApps: [],
                category: .other
            ),
            // URL scheme shape, plus an app that no longer exists on disk.
            HandlerEntry(
                id: "url:mailto",
                displayName: "mailto:",
                kind: .urlScheme,
                uti: nil,
                defaultApp: AppRef(
                    bundleID: "com.dead.Mailer",
                    displayName: "Dead Mailer",
                    bundleURL: nil,
                    exists: false
                ),
                alternativeApps: [],
                category: .urlSchemes
            ),
        ]
    }

    func test_roundTripPreservesEveryField() throws {
        let original = sampleEntries()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([HandlerEntry].self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_roundTripCoversEveryCategoryCase() throws {
        let entries = OpensWith.Category.allCases.map { category in
            HandlerEntry(
                id: "ext:.\(category.rawValue)",
                displayName: ".\(category.rawValue)",
                kind: .fileExtension,
                uti: nil,
                defaultApp: nil,
                alternativeApps: [],
                category: category
            )
        }
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([HandlerEntry].self, from: data)
        XCTAssertEqual(decoded.map(\.category), OpensWith.Category.allCases)
    }

    func test_kindEncodesAsAStableString() throws {
        let data = try JSONEncoder().encode(HandlerEntry.Kind.urlScheme)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"urlScheme\"")
    }

    // MARK: - Envelope

    func test_encodeThenDecodeRoundTripsTheEnvelope() throws {
        let captured = Date(timeIntervalSince1970: 1_759_395_272)  // 2026-10-02T08:54:32Z
        let data = try SnapshotCodec.encode(sampleEntries(), capturedAt: captured)

        let snapshot = try XCTUnwrap(SnapshotCodec.decode(data))

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.capturedAt, captured)
        XCTAssertEqual(snapshot.entries, sampleEntries())
    }

    /// The real guard against a silent key rename: this fixture is hand-written
    /// and checked in. If someone renames a CodingKey without bumping the schema
    /// version, this test fails.
    func test_decodesTheCheckedInWireFormatFixture() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "snapshot-v1", withExtension: "json", subdirectory: "Fixtures")
        )
        let snapshot = try XCTUnwrap(SnapshotCodec.decode(try Data(contentsOf: url)))

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.entries.count, 2)

        let pdf = try XCTUnwrap(snapshot.entries.first { $0.id == "ext:.pdf" })
        XCTAssertEqual(pdf.displayName, ".pdf")
        XCTAssertEqual(pdf.kind, .fileExtension)
        XCTAssertEqual(pdf.uti, "com.adobe.pdf")
        XCTAssertEqual(pdf.category, .documents)
        XCTAssertEqual(pdf.defaultApp?.bundleID, "com.apple.Preview")
        XCTAssertEqual(pdf.defaultApp?.displayName, "Preview")
        XCTAssertEqual(pdf.defaultApp?.exists, true)
        XCTAssertEqual(pdf.alternativeApps.map(\.bundleID), ["com.google.Chrome"])

        let mailto = try XCTUnwrap(snapshot.entries.first { $0.id == "url:mailto" })
        XCTAssertEqual(mailto.displayName, "mailto:")
        XCTAssertEqual(mailto.kind, .urlScheme)
        XCTAssertNil(mailto.uti)
        XCTAssertEqual(mailto.category, .urlSchemes)
        XCTAssertNil(mailto.defaultApp?.bundleURL)
        XCTAssertEqual(mailto.defaultApp?.exists, false)
        XCTAssertTrue(mailto.alternativeApps.isEmpty)
    }

    // MARK: - Cache-miss conditions

    func test_unknownSchemaVersionIsACacheMiss() throws {
        let json = #"{"schemaVersion":99,"capturedAt":"2026-10-02T08:54:32Z","entries":[]}"#
        XCTAssertNil(SnapshotCodec.decode(Data(json.utf8)))
    }

    func test_malformedJSONIsACacheMiss() {
        XCTAssertNil(SnapshotCodec.decode(Data("{ not json".utf8)))
    }

    func test_emptyDataIsACacheMiss() {
        XCTAssertNil(SnapshotCodec.decode(Data()))
    }

    /// Review Focus #1 — an empty entries array must not produce a timestamped
    /// banner floating over an empty table. It is a miss, so the app probes
    /// exactly as it would with no cache at all.
    func test_emptyEntriesArrayIsACacheMiss() {
        let json = #"{"schemaVersion":1,"capturedAt":"2026-10-02T08:54:32Z","entries":[]}"#
        XCTAssertNil(SnapshotCodec.decode(Data(json.utf8)))
    }

    /// Review Focus #2 — a hand-edited or truncated file missing a required key
    /// must come back nil, not crash.
    func test_missingRequiredKeyIsACacheMissNotACrash() {
        let json = """
        {"schemaVersion":1,"capturedAt":"2026-10-02T08:54:32Z","entries":[
          {"id":"ext:.pdf","displayName":".pdf","kind":"fileExtension","category":"documents"}
        ]}
        """
        XCTAssertNil(SnapshotCodec.decode(Data(json.utf8)))
    }

    /// Review Focus #4 — a capturedAt in the future (the user moved their system
    /// clock) is still a usable cache. Rejecting it would reintroduce the blank
    /// table this feature exists to remove.
    func test_futureCapturedAtIsStillAccepted() throws {
        let future = Date().addingTimeInterval(60 * 60 * 24 * 365)
        let data = try SnapshotCodec.encode(sampleEntries(), capturedAt: future)

        let snapshot = try XCTUnwrap(SnapshotCodec.decode(data))

        XCTAssertEqual(snapshot.capturedAt.timeIntervalSince1970,
                       future.timeIntervalSince1970,
                       accuracy: 1.0)
    }

    /// `Category`'s raw values are the wire contract (it has no explicit
    /// `CodingKeys`, unlike `HandlerEntry`/`AppRef`), but `test_roundTripCoversEveryCategoryCase`
    /// encodes and decodes with the same code, so a rename there would pass
    /// trivially. This pins the literal strings so a rename fails loudly.
    func test_categoryRawValuesAreTheWireContract() {
        XCTAssertEqual(OpensWith.Category.allCases.map(\.rawValue),
                       ["images", "documents", "audio", "video",
                        "codeText", "archives", "urlSchemes", "other"])
    }

    func test_encodedJSONHasSortedKeysForDeterminism() throws {
        let data = try SnapshotCodec.encode(sampleEntries(), capturedAt: Date())
        let text = String(decoding: data, as: UTF8.self)
        let capturedAtIndex = try XCTUnwrap(text.range(of: "\"capturedAt\""))
        let entriesIndex = try XCTUnwrap(text.range(of: "\"entries\""))
        let schemaIndex = try XCTUnwrap(text.range(of: "\"schemaVersion\""))
        XCTAssertTrue(capturedAtIndex.lowerBound < entriesIndex.lowerBound)
        XCTAssertTrue(entriesIndex.lowerBound < schemaIndex.lowerBound)
    }
}
