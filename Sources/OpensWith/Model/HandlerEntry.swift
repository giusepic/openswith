import Foundation

struct HandlerEntry: Identifiable, Hashable, Codable, Sendable {
    /// `String`-backed so the on-disk encoding is stable and readable.
    /// Changing a raw value here is a wire-format change — bump `Snapshot.currentSchemaVersion`.
    enum Kind: String, Hashable, Codable, Sendable {
        case fileExtension
        case urlScheme
    }

    let id: String              // "ext:.md" or "url:mailto"
    let displayName: String     // ".md" or "mailto:"
    let kind: Kind
    let uti: String?            // public.markdown
    let defaultApp: AppRef?
    let alternativeApps: [AppRef]
    let category: Category

    /// Declared explicitly so the JSON field names are pinned independently of
    /// the Swift property names: renaming a property here must not silently
    /// invalidate every snapshot already on disk. Changing a key is a
    /// wire-format change — bump `Snapshot.currentSchemaVersion`.
    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case kind
        case uti
        case defaultApp
        case alternativeApps
        case category
    }
}
