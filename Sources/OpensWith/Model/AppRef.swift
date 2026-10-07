import Foundation

struct AppRef: Hashable, Identifiable, Codable, Sendable {
    let bundleID: String
    let displayName: String
    let bundleURL: URL?
    /// Whether the bundle existed on disk **at capture time**. Stored as
    /// recorded and never re-verified on load — see the design doc's
    /// "Recorded vs. live facts".
    let exists: Bool

    var id: String { bundleID }

    /// See the note on `HandlerEntry.CodingKeys`.
    enum CodingKeys: String, CodingKey {
        case bundleID
        case displayName
        case bundleURL
        case exists
    }
}
