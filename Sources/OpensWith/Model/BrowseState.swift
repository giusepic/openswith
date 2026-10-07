import Foundation

enum BrowseMode: Hashable {
    case categories
    case apps
}

enum BrowseFilter: Hashable {
    case allCategories
    case category(Category)
    case app(bundleID: String)
}

enum AppSortKey: Hashable {
    case name
    case count
}

enum SortDirection: Hashable {
    case ascending
    case descending
}
