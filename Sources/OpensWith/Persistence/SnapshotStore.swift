import Foundation

/// Reads and writes snapshots under Application Support.
///
/// Layout:
/// ```
/// ~/Library/Application Support/OpensWith/
///   cache/
///     latest.json          ← overwritten on every successful probe
///   baselines/             ← reserved: Baseline + diff, same codec
///     2026-10-02T0914.json   explicitly captured, never auto-overwritten
/// ```
/// Two directories rather than one file serving both roles, so a user-pinned
/// "known good" baseline can never be silently clobbered by a routine refresh.
///
/// Every function here is synchronous and nonisolated so callers can run them
/// off the main actor.
enum SnapshotStore {

    /// Named literally rather than derived from `Bundle.main.bundleIdentifier`,
    /// which is nil under `swift run` (no app bundle). The app is not sandboxed,
    /// so a readable directory name is also the better convention.
    static let defaultBaseDirectory: URL = {
        let applicationSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport.appendingPathComponent("OpensWith", isDirectory: true)
    }()

    static func cacheFileURL(baseDirectory: URL = defaultBaseDirectory) -> URL {
        baseDirectory
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("latest.json", isDirectory: false)
    }

    static func load(baseDirectory: URL = defaultBaseDirectory) -> Snapshot? {
        guard let data = try? Data(contentsOf: cacheFileURL(baseDirectory: baseDirectory)) else {
            return nil
        }
        return SnapshotCodec.decode(data)
    }

    /// Writes atomically, so a kill mid-write cannot leave a truncated file.
    ///
    /// Failures are swallowed: this app has no logging infrastructure, the user
    /// cannot act on a cache-write failure, and the feature degrades to exactly
    /// today's behaviour (a blank table on the next cold start).
    static func save(_ entries: [HandlerEntry],
                     capturedAt: Date = Date(),
                     baseDirectory: URL = defaultBaseDirectory) {
        // An empty scan is never a legitimate result — never let one poison the cache.
        guard !entries.isEmpty else { return }

        let fileURL = cacheFileURL(baseDirectory: baseDirectory)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try SnapshotCodec.encode(entries, capturedAt: capturedAt)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Intentionally ignored — see the doc comment.
        }
    }
}
