import Foundation
import UniformTypeIdentifiers

enum Category: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case images
    case documents
    case audio
    case video
    case codeText
    case archives
    case urlSchemes
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .images: return "Images"
        case .documents: return "Documents"
        case .audio: return "Audio"
        case .video: return "Video"
        case .codeText: return "Code & Text"
        case .archives: return "Archives"
        case .urlSchemes: return "URL Schemes"
        case .other: return "Other"
        }
    }

    /// SF Symbol shown beside the category in the sidebar.
    var symbolName: String {
        switch self {
        case .images: return "photo"
        case .documents: return "doc.richtext"
        case .audio: return "music.note"
        case .video: return "film"
        case .codeText: return "chevron.left.forwardslash.chevron.right"
        case .archives: return "archivebox"
        case .urlSchemes: return "link"
        case .other: return "questionmark.square.dashed"
        }
    }

    /// Symbol for the "All" row, which spans every category.
    static let allSymbolName = "square.grid.2x2"
}

enum Categorizer {
    /// Maps a UTI to a display category. URL schemes are categorised at the
    /// call site (they have no UTI), so this only handles file types.
    ///
    /// Order matters: UTType conformance is transitive, so the narrower branch
    /// has to come first. `.rtf` conforms to `.text`, so documents is checked
    /// before codeText — otherwise RTF would land in Code & Text.
    static func categorize(uti: String?) -> Category {
        guard let uti, let type = UTType(uti) else { return .other }

        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .audio) { return .audio }
        // `.video` conforms to `.movie`, so the movie check subsumes it.
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .archive) { return .archives }
        if type.conforms(to: .pdf) || type.conforms(to: .spreadsheet)
            || type.conforms(to: .presentation) || type.conforms(to: .rtf) { return .documents }
        // `.sourceCode` and `.plainText` both conform to `.text`.
        if type.conforms(to: .text) { return .codeText }
        return .other
    }
}
