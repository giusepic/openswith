import Foundation

/// Renders handler entries as RFC 4180 CSV.
///
/// Pure and nonisolated — no AppKit, no filesystem. `ExportPanel` owns picking a
/// destination and writing; this owns what the bytes say.
enum CSVExporter {

    static let header = ["Type", "Name", "UTI", "Category", "Default app", "Bundle ID", "App path"]

    /// The text of the file, CRLF-separated and trailing-newline terminated.
    ///
    /// Rows are sorted by name, ascending and case-insensitively, regardless of
    /// how the table happens to be sorted: the table's sort order is `@State`
    /// inside the view, and a stable order here means two exports of unchanged
    /// data are byte-identical — which is what makes diffing them worthwhile.
    static func csv(for entries: [HandlerEntry]) -> String {
        let sorted = entries.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        let lines = [header] + sorted.map(fields(for:))
        return lines.map { $0.map { escape(neutralize($0)) }.joined(separator: ",") }
            .joined(separator: "\r\n")
            + "\r\n"
    }

    /// The file's bytes: UTF-8 with a BOM.
    ///
    /// The BOM and the CRLF endings exist for Excel, which otherwise reads a
    /// UTF-8 CSV as the system's legacy encoding and mangles any non-ASCII app
    /// name. Numbers and every text editor are happy either way.
    static func data(for entries: [HandlerEntry]) -> Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(csv(for: entries).utf8)
    }

    /// A nil UTI or a missing app yields an empty cell, never a placeholder:
    /// "Not assigned" and "—" are strings the UI shows a human, and writing them
    /// into a data file would make every consumer parse them back out.
    private static func fields(for entry: HandlerEntry) -> [String] {
        [
            entry.kind == .fileExtension ? "Extension" : "URL scheme",
            entry.displayName,
            entry.uti ?? "",
            entry.category.displayName,
            entry.defaultApp?.displayName ?? "",
            entry.defaultApp?.bundleID ?? "",
            entry.defaultApp?.bundleURL.map(\.path) ?? "",
        ]
    }

    /// Characters that make a spreadsheet read the cell as a formula rather than
    /// as text. Tab and CR count because the leading whitespace is stripped before
    /// the rest of the cell is interpreted.
    private static let formulaLeads: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    /// Defuses spreadsheet formula injection by prefixing a single quote.
    ///
    /// RFC 4180 quoting governs *parsing* and does nothing here: Excel, LibreOffice
    /// and Numbers evaluate a cell beginning with `=` whether or not it arrived
    /// wrapped in quotes. The hostile input is real — `displayName` comes from a
    /// third party's `CFBundleDisplayName`, and a URL scheme only has to end in
    /// `:` to survive `LSDumpParser` — so an app named `=HYPERLINK(...)` would
    /// otherwise become a live formula the moment someone opened the export.
    ///
    /// The leading `'` is the spreadsheet convention for "treat the rest as text";
    /// it is consumed on display, so the cell still reads as the original string.
    /// Applied to every column rather than just the two known-hostile ones, so a
    /// new column cannot reintroduce the hole by being added without this in mind.
    ///
    /// Nothing legitimate here starts with one of these: extensions start with `.`,
    /// schemes with a letter, UTIs and bundle IDs are reverse-DNS, paths with `/`,
    /// and category names are our own.
    private static func neutralize(_ field: String) -> String {
        guard let first = field.first, formulaLeads.contains(first) else { return field }
        return "'" + field
    }

    /// RFC 4180: wrap in quotes when the field holds a comma, quote, CR or LF,
    /// and double any quote inside. App paths and app names are the realistic
    /// triggers ("/Applications/Acme, Pro.app").
    ///
    /// Runs *after* `neutralize`, so a payload needing both treatments gets the
    /// prefix inside the quotes — quoting a string that already starts with `'`
    /// keeps the apostrophe where the spreadsheet will act on it.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
