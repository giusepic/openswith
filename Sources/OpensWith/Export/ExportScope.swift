import Foundation

/// What an export covers. Chosen in the save panel at export time rather than
/// fixed, because both readings are legitimate: "the images I'm looking at" and
/// "everything, as an audit record".
enum ExportScope: Hashable, CaseIterable {
    /// The rows currently on screen — sidebar filter and search applied.
    case visible
    /// Every entry, regardless of what the UI is showing.
    case all

    var displayName: String {
        switch self {
        case .visible: return "Visible rows"
        case .all: return "All entries"
        }
    }
}
