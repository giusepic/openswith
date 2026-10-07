import XCTest
@testable import OpensWith

final class CSVExporterTests: XCTestCase {

    private func entry(_ name: String,
                       kind: HandlerEntry.Kind = .fileExtension,
                       uti: String? = nil,
                       category: OpensWith.Category = .other,
                       app: AppRef? = nil) -> HandlerEntry {
        HandlerEntry(
            id: "\(kind == .fileExtension ? "ext" : "url"):\(name)",
            displayName: name,
            kind: kind,
            uti: uti,
            defaultApp: app,
            alternativeApps: [],
            category: category
        )
    }

    private func app(_ bundleID: String, _ displayName: String, path: String?) -> AppRef {
        AppRef(bundleID: bundleID,
               displayName: displayName,
               bundleURL: path.map { URL(fileURLWithPath: $0) },
               exists: true)
    }

    private func rows(_ csv: String) -> [String] {
        csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    }

    // MARK: - Shape

    func test_headerRowIsTheAuditSet() {
        let csv = CSVExporter.csv(for: [])
        XCTAssertEqual(rows(csv), ["Type,Name,UTI,Category,Default app,Bundle ID,App path"])
    }

    func test_fileExtensionRow_carriesEveryColumn() {
        let csv = CSVExporter.csv(for: [
            entry(".pdf",
                  uti: "com.adobe.pdf",
                  category: .documents,
                  app: app("com.apple.Preview", "Preview", path: "/System/Applications/Preview.app"))
        ])
        XCTAssertEqual(rows(csv).last,
                       "Extension,.pdf,com.adobe.pdf,Documents,Preview,com.apple.Preview,/System/Applications/Preview.app")
    }

    func test_urlSchemeRow_usesTheSchemeLabelAndAnEmptyUTI() {
        let csv = CSVExporter.csv(for: [
            entry("mailto:",
                  kind: .urlScheme,
                  category: .urlSchemes,
                  app: app("com.apple.mail", "Mail", path: "/System/Applications/Mail.app"))
        ])
        XCTAssertEqual(rows(csv).last,
                       "URL scheme,mailto:,,URL Schemes,Mail,com.apple.mail,/System/Applications/Mail.app")
    }

    /// "Not assigned" and "—" are UI placeholders. A data file leaves the cell empty.
    func test_unassignedEntry_leavesAppColumnsEmpty() {
        let csv = CSVExporter.csv(for: [entry(".xyz", uti: "com.example.xyz", category: .other)])
        XCTAssertEqual(rows(csv).last, "Extension,.xyz,com.example.xyz,Other,,,")
    }

    func test_appWithoutABundleURL_leavesOnlyThePathEmpty() {
        let csv = CSVExporter.csv(for: [
            entry(".png", uti: "public.png", category: .images,
                  app: app("com.apple.Preview", "Preview", path: nil))
        ])
        XCTAssertEqual(rows(csv).last, "Extension,.png,public.png,Images,Preview,com.apple.Preview,")
    }

    // MARK: - RFC 4180 quoting

    func test_fieldContainingACommaIsQuoted() {
        let csv = CSVExporter.csv(for: [
            entry(".key", uti: "com.apple.keynote", category: .documents,
                  app: app("com.acme.suite", "Acme Office, Pro", path: "/Applications/Acme, Pro.app"))
        ])
        XCTAssertEqual(rows(csv).last,
                       "Extension,.key,com.apple.keynote,Documents,\"Acme Office, Pro\",com.acme.suite,\"/Applications/Acme, Pro.app\"")
    }

    func test_fieldContainingAQuoteIsQuotedAndItsQuotesDoubled() {
        let csv = CSVExporter.csv(for: [
            entry(".txt", uti: "public.plain-text", category: .codeText,
                  app: app("com.acme.editor", "The \"Best\" Editor", path: nil))
        ])
        XCTAssertEqual(rows(csv).last,
                       "Extension,.txt,public.plain-text,Code & Text,\"The \"\"Best\"\" Editor\",com.acme.editor,")
    }

    func test_fieldContainingANewlineIsQuoted() {
        let csv = CSVExporter.csv(for: [
            entry(".odd", uti: nil, category: .other,
                  app: app("com.acme.odd", "Line\nBreak", path: nil))
        ])
        XCTAssertTrue(csv.contains("\"Line\nBreak\""), csv)
    }

    func test_plainFieldsAreNotQuoted() {
        let csv = CSVExporter.csv(for: [
            entry(".png", uti: "public.png", category: .images,
                  app: app("com.apple.Preview", "Preview", path: "/System/Applications/Preview.app"))
        ])
        XCTAssertFalse(csv.contains("\""), csv)
    }

    // MARK: - Formula injection

    /// RFC 4180 quoting governs parsing, not what Excel does on open: a field
    /// starting with `=` is evaluated as a formula whether or not it is quoted.
    /// App names come from a third party's `CFBundleDisplayName`, so a hostile
    /// app name would otherwise land in the export as a live formula.
    func test_appNameStartingWithEqualsIsNeutralized() {
        let csv = CSVExporter.csv(for: [
            entry(".xyz", uti: nil, category: .other,
                  app: app("com.evil.app", "=1+1", path: nil))
        ])
        XCTAssertEqual(rows(csv).last, "Extension,.xyz,,Other,'=1+1,com.evil.app,")
    }

    func test_everyFormulaLeadCharacterIsNeutralized() {
        for lead in ["=", "+", "-", "@"] {
            let csv = CSVExporter.csv(for: [
                entry(".xyz", uti: nil, category: .other,
                      app: app("com.evil.app", "\(lead)CMD", path: nil))
            ])
            XCTAssertEqual(rows(csv).last,
                           "Extension,.xyz,,Other,'\(lead)CMD,com.evil.app,",
                           "lead character \(lead.debugDescription) was not neutralized")
        }
    }

    /// Tab and CR are formula leads too, and both arrive already needing RFC 4180
    /// quoting — the two rules have to compose, not compete.
    func test_tabAndCarriageReturnLeadsAreNeutralized() {
        for lead in ["\t", "\r"] {
            let csv = CSVExporter.csv(for: [
                entry(".xyz", uti: nil, category: .other,
                      app: app("com.evil.app", "\(lead)=CMD", path: nil))
            ])
            XCTAssertTrue(csv.contains("'\(lead)=CMD"),
                          "lead character \(lead.debugDescription) was not neutralized: \(csv.debugDescription)")
        }
    }

    /// A payload that also needs quoting must get both treatments, in that order.
    func test_neutralizedFieldIsStillQuotedWhenItNeedsToBe() {
        let csv = CSVExporter.csv(for: [
            entry(".xyz", uti: nil, category: .other,
                  app: app("com.evil.app", "=HYPERLINK(\"http://evil\",\"x\")", path: nil))
        ])
        XCTAssertEqual(rows(csv).last,
                       "Extension,.xyz,,Other,\"'=HYPERLINK(\"\"http://evil\"\",\"\"x\"\")\",com.evil.app,")
    }

    /// Every column is neutralized, not just the app name. A URL scheme survives
    /// `LSDumpParser` with any lead character — only a trailing `:` is required —
    /// so the Name column is third-party-controlled too.
    func test_neutralizationAppliesToTheNameColumn() {
        let csv = CSVExporter.csv(for: [
            entry("=evil:", kind: .urlScheme, category: .urlSchemes)
        ])
        XCTAssertEqual(rows(csv).last, "URL scheme,'=evil:,,URL Schemes,,,")
    }

    /// The guard must not fire on ordinary data: every extension starts with `.`
    /// and no column is numeric, so nothing legitimate should pick up a prefix.
    func test_ordinaryFieldsAreNotPrefixed() {
        let csv = CSVExporter.csv(for: [
            entry(".pdf", uti: "com.adobe.pdf", category: .documents,
                  app: app("com.apple.Preview", "Preview", path: "/System/Applications/Preview.app"))
        ])
        XCTAssertFalse(csv.contains("'"), csv)
    }

    // MARK: - Ordering

    /// The table's sort order is view state, not store state. The export has its
    /// own stable order so two exports of the same data are byte-identical.
    func test_rowsAreSortedByNameAscendingCaseInsensitively() {
        let csv = CSVExporter.csv(for: [
            entry(".Png"),
            entry(".md"),
            entry(".avi"),
        ])
        XCTAssertEqual(rows(csv).dropFirst().map { $0.components(separatedBy: ",")[1] },
                       [".avi", ".md", ".Png"])
    }

    // MARK: - Encoding

    func test_dataIsUTF8WithABOMAndCRLFLineEndings() {
        let data = CSVExporter.data(for: [entry(".md")])
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])

        let text = String(data: data.dropFirst(3), encoding: .utf8)
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.hasSuffix("\r\n"), text!.debugDescription)
    }

    func test_dataRoundTripsNonASCIIAppNames() {
        let data = CSVExporter.data(for: [
            entry(".md", uti: "net.daringfireball.markdown", category: .codeText,
                  app: app("com.acme.app", "Éditeur 日本語", path: nil))
        ])
        let text = String(data: data.dropFirst(3), encoding: .utf8)
        XCTAssertTrue(text?.contains("Éditeur 日本語") == true, text ?? "nil")
    }
}
