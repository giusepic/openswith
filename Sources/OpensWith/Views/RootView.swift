import SwiftUI

struct RootView: View {
    @StateObject var store = AppStore()
    @EnvironmentObject var updates: UpdateChecker

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } content: {
            VStack(spacing: 0) {
                UpdateBannerView()
                LoadingBannerView()
                HandlersTableView()
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 530, max: 700)
        } detail: {
            DetailView()
                // Let the detail pane absorb extra window width once the
                // sidebar and table reach their preferred limits.
                .navigationSplitViewColumnWidth(min: 330, ideal: 390)
        }
        .environmentObject(store)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ExportPanel.run(store: store)
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e", modifiers: .command)
                // Nothing to write before the first probe lands.
                .disabled(store.entries.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading || store.pendingChangeEntryID != nil)
            }
        }
        .task { await store.start() }
        // Separate from the probe's task so a slow or hung network call can
        // never delay the table appearing.
        .task { await updates.checkAutomatically() }
        .frame(minWidth: 900, minHeight: 560)
    }
}
