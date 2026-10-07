import SwiftUI

struct LoadingBannerView: View {
    enum Presentation { case banner, sidebar }

    @EnvironmentObject var store: AppStore
    var presentation: Presentation = .banner

    var body: some View {
        if presentation == .sidebar {
            sidebarStatus
        } else {
            failureBanner
        }
    }

    // Routine progress lives in the sidebar footer; failures remain prominent
    // above the table, where the full explanation has room to wrap.
    @ViewBuilder
    private var failureBanner: some View {
        switch store.bannerState {
        case .hidden, .probing, .refreshingFromCache:
            EmptyView()

        case .failed(let reason):
            banner(background: Color.orange.opacity(0.1)) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Couldn't read the Launch Services database — \(reason)")
                    .font(AppTypography.caption)
            }

        case .failedShowingCache(let since):
            banner(background: Color.orange.opacity(0.1)) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Couldn't refresh — showing results from \(Self.age(since)).")
                    .font(AppTypography.caption)
            }
        }
    }

    private var sidebarStatus: some View {
        HStack(alignment: .top, spacing: 8) {
            if store.isLoading || store.pendingChangeEntryID != nil {
                ProgressView().controlSize(.small)
                    .accessibilityLabel(statusTitle)
            } else {
                Image(systemName: store.failureReason != nil ? "exclamationmark.triangle.fill" :
                        store.entries.isEmpty ? "circle.dashed" : "checkmark.circle.fill")
                    .foregroundStyle(store.failureReason != nil ? Color.orange :
                                     store.entries.isEmpty ? Color.secondary : Color.green)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                if let since = store.cacheCapturedAt {
                    Text("Saved results from \(Self.age(since))")
                        .font(AppTypography.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .font(AppTypography.caption)
        .foregroundStyle(.secondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(store.failureReason ?? statusTitle)
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        if store.pendingChangeEntryID != nil { return "Waiting for confirmation…" }
        if store.isLoading { return store.entries.isEmpty ? "Scanning registered types…" : "Refreshing…" }
        if store.failureReason != nil { return "Couldn't refresh" }
        return store.entries.isEmpty ? "Ready to scan" : "Scan complete"
    }

    @ViewBuilder
    private func banner<Content: View>(background: Color = .clear,
                                       @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(background)
    }

    /// Formatted here rather than in the store, so `BannerState` stays a plain
    /// value and its tests stay free of locale and date-formatting flakiness.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static func age(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
