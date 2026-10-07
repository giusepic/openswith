import SwiftUI
import AppKit

struct HandlersTableView: View {
    @EnvironmentObject var store: AppStore
    @State private var sortOrder = [KeyPathComparator(\HandlerEntry.displayName)]

    var body: some View {
        let rows = sortedEntries
        VStack(spacing: 0) {
            listHeader(count: rows.count)
            Divider()
            table(rows: rows)
                .overlay {
                    if rows.isEmpty, !store.isLoading {
                        emptyState
                    }
                }
            Divider()
            HStack {
                Text(store.searchText.isEmpty
                     ? "\(rows.count.formatted()) \(rows.count == 1 ? "entry" : "entries")"
                     : "\(rows.count.formatted()) of \(store.count(for: store.selectedFilter).formatted()) entries")
                Spacer()
            }
            .font(AppTypography.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search types or apps")
    }

    private func listHeader(count: Int) -> some View {
        HStack(spacing: 10) {
            if let app = filteredApp, let url = app.bundleURL {
                AppIcon(url: url, size: 32)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(filterTitle)
                    .font(AppTypography.heading)
                    .lineLimit(1)
                Text("\(count.formatted()) \(store.searchText.isEmpty ? "registered" : "matching") \(count == 1 ? "type" : "types")")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filteredApp: AppRef? {
        guard case .app(let bundleID) = store.selectedFilter else { return nil }
        return store.appsWithDefaults.first { $0.bundleID == bundleID }
    }

    private var filterTitle: String {
        switch store.selectedFilter {
        case .allCategories: return "All types"
        case .category(let category): return category.displayName
        case .app: return filteredApp?.displayName ?? "Apps"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(store.searchText.isEmpty ? "No registered types" : "No matching types")
                .font(AppTypography.appName)
            Text(store.searchText.isEmpty ? "Refresh to scan your Mac." : "Try another name or clear the search.")
                .font(AppTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func table(rows: [HandlerEntry]) -> some View {
        Table(rows, selection: $store.selectedEntryID, sortOrder: $sortOrder) {
            TableColumn("Type", value: \.displayName) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.symbolName)
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(entry.displayName)
                }
                .frame(height: 24)
            }
            .width(min: 90, ideal: 130)
            TableColumn("Default app",
                        value: \.defaultAppNameOrPlaceholder) { entry in
                if let app = entry.defaultApp {
                    HStack(spacing: 8) {
                        if let url = app.bundleURL {
                            AppIcon(url: url, size: 20)
                        }
                        Text(app.displayName)
                            .lineLimit(1)
                    }
                    .frame(height: 24)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                        .frame(height: 24)
                }
            }
            .width(min: 150, ideal: 230)
        }
        .font(AppTypography.body)
        // Avoid drawing alternating stripes into the unused space below rows.
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        // Rebuild the table instead of letting AppKit diff its way from a small
        // row set to a large one. `Table` animates an incremental update, and
        // the cost of that update is not proportional to the number of rows
        // added — measured on ~1,500 entries, growing from 28 rows blocks the
        // main thread for ~3s, while 619 -> 1,509 (nearly twice as many rows
        // inserted) costs ~60ms, and building the same 1,509 rows from empty
        // costs ~45ms. The expensive path is AppKit re-measuring automatic row
        // heights and tearing down hosting views for every recycled row.
        //
        // Changing the identity discards the old table and builds a new one,
        // which takes the cheap from-empty path: the worst case drops from
        // ~3,000ms to ~110ms. The cost is losing the row-insertion animation
        // and resetting scroll position on a filter change — both of which are
        // what you want anyway when the row set is replaced wholesale.
        //
        // `isSearching` is a Bool, not the search text: re-identifying on every
        // keystroke would rebuild the table per character. Only crossing the
        // empty/non-empty boundary changes the row set drastically enough to
        // matter; narrowing within a search keeps the cheap diff.
        // Also rebuild when rows first arrive (or a no-results search recovers).
        // Otherwise SwiftUI's empty-to-populated update re-enters AppKit's row
        // height calculation and logs the NSTableView delegate warning at launch.
        .id(RowSetIdentity(filter: store.selectedFilter,
                           isSearching: !store.searchText.isEmpty,
                           hasRows: !rows.isEmpty))
    }

    private var sortedEntries: [HandlerEntry] {
        store.filteredEntries.sorted(using: sortOrder)
    }
}

private struct RowSetIdentity: Hashable {
    let filter: BrowseFilter
    let isSearching: Bool
    let hasRows: Bool
}

extension HandlerEntry {
    var defaultAppNameOrPlaceholder: String { defaultApp?.displayName ?? "—" }
}

struct AppIcon: View {
    let url: URL
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: IconCache.icon(for: url))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// `NSWorkspace.icon(forFile:)` is not a cheap accessor — each call goes through
/// LaunchServices to resolve the bundle before it returns the image. Rows are
/// recycled constantly while scrolling and refiltering, so the same ~100 app
/// icons get re-resolved thousands of times.
///
/// Keyed by path rather than by entry: many extensions share one app, so the
/// cache stays at roughly the number of installed apps regardless of row count.
/// Never invalidated — a changed icon is cosmetic and corrects on next launch,
/// which is a better trade than paying the lookup on every row recycle.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        let key = url.path
        if let hit = cache[key] { return hit }
        let image = NSWorkspace.shared.icon(forFile: key)
        cache[key] = image
        return image
    }
}
