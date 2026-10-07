import Foundation

/// A dotted numeric version, compared component by component as integers.
///
/// This type exists because string comparison gets it wrong in a way that is
/// invisible until the tenth release: lexically `"0.10.0" < "0.9.0"`, so a
/// checker comparing raw strings would quietly stop announcing updates forever
/// after v0.9.0. Covered by `SemanticVersionTests.test_comparesNumericallyNotLexically`.
///
/// Parsing is deliberately strict. Anything that isn't digits-and-dots —
/// `"latest"`, `"1.0.0-beta"`, `"1.0.0+build7"` — returns nil rather than
/// being coerced, because a wrong parse produces a confidently wrong comparison.
/// A nil here means the caller stays silent, which is always the safe outcome.
struct SemanticVersion: Equatable, Comparable {

    /// Each dotted component, in order. Never empty.
    let components: [Int]

    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // GitHub tags are conventionally `v`-prefixed ("v1.2.3") while
        // CFBundleShortVersionString never is. Normalize so the two compare.
        var body = trimmed
        if let first = body.first, first == "v" || first == "V" {
            body.removeFirst()
        }
        guard !body.isEmpty else { return nil }

        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var parsed: [Int] = []
        parsed.reserveCapacity(parts.count)
        for part in parts {
            // `Int(...)` would accept a leading "-" or "+"; digits-only keeps
            // "-1.0.0" and "1.0.0+build7" out. An empty part catches "1..2".
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part)
            else { return nil }
            parsed.append(value)
        }

        self.components = parsed
    }

    /// Compares positionally, treating a missing trailing component as zero so
    /// `1.0` and `1.0.0` are the same release rather than one looking newer.
    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return false }
        }
        return true
    }
}
