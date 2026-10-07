import SwiftUI
import UniformTypeIdentifiers

// Keep the reading sizes consistent across the three panes.
enum AppTypography {
    static let body = Font.system(size: 14)
    static let secondary = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let sectionHeading = Font.system(size: 13, weight: .semibold)
    static let heading = Font.system(size: 17, weight: .semibold)
    static let appName = Font.system(size: 15, weight: .semibold)
    static let technical = Font.system(size: 13, design: .monospaced)
}

// Presentation only: these properties aren't part of the snapshot format.
extension Category {
    var tint: Color {
        switch self {
        case .images: return .blue
        case .documents: return .purple
        case .audio: return .orange
        case .video: return .purple
        case .codeText: return .blue
        case .archives: return .green
        case .urlSchemes: return .blue
        case .other: return .secondary
        }
    }
}

extension HandlerEntry {
    var symbolName: String {
        if kind == .urlScheme { return "link" }
        return category == .other ? "doc" : category.symbolName
    }

    var typeDescription: String {
        if kind == .urlScheme { return "URL scheme" }
        if let uti, let description = UTType(uti)?.localizedDescription,
           !description.isEmpty {
            return description
        }
        return "File extension"
    }
}

struct InspectorCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
    }
}
