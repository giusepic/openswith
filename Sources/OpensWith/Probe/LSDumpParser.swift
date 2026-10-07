import Foundation

struct ParseResult {
    let extensions: Set<String>
    let urlSchemes: [String]
}

enum LSDumpParser {
    private static let stanzaSeparator = String(repeating: "-", count: 80)

    static func parse(_ dump: String) -> ParseResult {
        var extensions: Set<String> = []
        var schemes: Set<String> = []

        for stanza in dump.components(separatedBy: stanzaSeparator) {
            if isStanza("type", stanza) {
                extensions.formUnion(parseExtensions(stanza))
            } else if isStanza("claim", stanza) {
                schemes.formUnion(parseClaimSchemes(stanza))
            }
        }
        return ParseResult(extensions: extensions, urlSchemes: schemes.sorted())
    }

    private static func isStanza(_ kind: String, _ stanza: String) -> Bool {
        let marker = "\(kind) id:"
        return stanza.hasPrefix(marker) || stanza.contains("\n\(marker)")
    }

    /// File extensions live in a `type` stanza's `tags:` line, mixed in with
    /// MIME types, OSTypes and pasteboard names — only the dot-prefixed ones
    /// are extensions.
    private static func parseExtensions(_ stanza: String) -> [String] {
        let tagsRaw = field(named: "tags", in: stanza) ?? ""
        return tagsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix(".") }
    }

    private static func parseClaimSchemes(_ stanza: String) -> [String] {
        let bindingsRaw = field(named: "bindings", in: stanza) ?? ""
        return bindingsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasSuffix(":") && !$0.contains(" ") && !$0.hasPrefix(".") }
            .map { String($0.dropLast()) }
            .filter { !$0.isEmpty }
    }

    /// Find the first top-level (non-indented) field with the given name in a stanza.
    private static func field(named name: String, in stanza: String) -> String? {
        let prefix = "\(name):"
        for line in stanza.split(separator: "\n", omittingEmptySubsequences: false) {
            // Top-level fields are not indented.
            guard !line.hasPrefix("\t"), !line.hasPrefix(" ") else { continue }
            if line.hasPrefix(prefix) {
                let value = line.dropFirst(prefix.count)
                return value.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
