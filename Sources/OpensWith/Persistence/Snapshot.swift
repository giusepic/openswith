import Foundation

/// A recorded scan of the system's default handlers.
///
/// This is a **durable, versioned format**, not a throwaway render cache: the
/// Baseline + diff and Menu bar watcher features are both designed to read it.
/// Changing any `CodingKeys` entry or enum raw value in the stored types is a
/// wire-format change and requires bumping `currentSchemaVersion`.
struct Snapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let capturedAt: Date
    let entries: [HandlerEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case capturedAt
        case entries
    }
}

enum SnapshotCodec {

    static func encode(_ entries: [HandlerEntry], capturedAt: Date) throws -> Data {
        let snapshot = Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            capturedAt: capturedAt,
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Deterministic output, so the file is hand-diffable — which the future
        // diff feature will appreciate.
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// Returns `nil` for every unusable input rather than throwing. A missing,
    /// corrupt, future-versioned or empty snapshot is a **cache miss**, not an
    /// error: there is no action the user could take, so nothing is surfaced and
    /// the app proceeds exactly as it does with no cache at all.
    static func decode(_ data: Data) -> Snapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return nil }
        guard snapshot.schemaVersion == Snapshot.currentSchemaVersion else { return nil }
        // An empty scan is never written, so an empty one on disk is damage.
        // Treating it as a hit would show a timestamped banner over an empty table.
        guard !snapshot.entries.isEmpty else { return nil }
        return snapshot
    }
}
