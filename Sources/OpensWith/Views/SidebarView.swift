import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            modePicker
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            Group {
                switch store.browseMode {
                case .categories:
                    CategorySidebar()
                case .apps:
                    AppSidebar()
                }
            }
            Divider()
            LoadingBannerView(presentation: .sidebar)
        }
        .font(AppTypography.body)
    }

    private var modePicker: some View {
        Picker("Browse by", selection: Binding(
            get: { store.browseMode },
            set: { store.setBrowseMode($0) }
        )) {
            Text("Categories").tag(BrowseMode.categories)
            Text("Apps").tag(BrowseMode.apps)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Browse by")
    }
}

private struct CategorySidebar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List(selection: $store.selectedFilter) {
            Section {
                row(.allCategories, label: "All types", symbol: Category.allSymbolName, tint: .accentColor)
                ForEach(Category.allCases) { c in
                    row(.category(c), label: c.displayName, symbol: c.symbolName, tint: c.tint)
                }
            } header: {
                Text("Library").font(AppTypography.caption)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func row(_ filter: BrowseFilter, label: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(store.selectedFilter == filter ? Color.white.opacity(0.85) : tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
            Text(label)
            Spacer()
            Text(store.count(for: filter).formatted())
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(minHeight: 28)
        .tag(filter)
    }
}

private struct AppSidebar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if store.appsWithDefaults.isEmpty {
            emptyState
        } else {
            List(selection: $store.selectedFilter) {
                Section {
                    ForEach(store.appsWithDefaults) { app in
                        appRow(app)
                    }
                } header: {
                    AppSortHeader()
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "app.dashed")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No apps with defaults")
                .font(AppTypography.appName)
            Text("Refresh or switch to Categories.")
                .font(AppTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func appRow(_ app: AppRef) -> some View {
        HStack(spacing: 10) {
            if let url = app.bundleURL {
                AppIcon(url: url, size: 20)
            } else {
                Image(systemName: "app")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            Text(app.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(app.displayName)
            Spacer()
            Text(store.count(for: .app(bundleID: app.bundleID)).formatted())
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(minHeight: 28)
        .tag(BrowseFilter.app(bundleID: app.bundleID))
    }
}

private struct AppSortHeader: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack {
            headerButton(label: "Name", key: .name)
            Spacer()
            headerButton(label: "Count", key: .count)
        }
        .font(AppTypography.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func headerButton(label: String, key: AppSortKey) -> some View {
        let isActive = store.appSortKey == key
        Button {
            if isActive {
                store.appSortDirection = (store.appSortDirection == .ascending) ? .descending : .ascending
            } else {
                store.appSortKey = key
                // Default direction: ascending for Name, descending for Count.
                store.appSortDirection = (key == .name) ? .ascending : .descending
            }
        } label: {
            HStack(spacing: 2) {
                Text(label)
                if isActive {
                    Image(systemName: store.appSortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sortTooltip(label: label, isActive: isActive))
        .accessibilityLabel(sortAccessibilityLabel(label: label, isActive: isActive))
    }

    private func sortTooltip(label: String, isActive: Bool) -> String {
        guard isActive else { return "Sort by \(label.lowercased())" }
        return store.appSortDirection == .ascending
            ? "Sort by \(label.lowercased()) descending"
            : "Sort by \(label.lowercased()) ascending"
    }

    private func sortAccessibilityLabel(label: String, isActive: Bool) -> String {
        guard isActive else { return "Sort by \(label.lowercased())" }
        let dir = store.appSortDirection == .ascending ? "ascending" : "descending"
        return "Sort by \(label.lowercased()), currently \(dir)"
    }
}
