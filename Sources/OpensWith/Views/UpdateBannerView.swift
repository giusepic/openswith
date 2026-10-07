import SwiftUI
import AppKit

/// Sits above `LoadingBannerView`. Kept separate because that banner reports
/// probe progress and shares no state, styling lifecycle, or dismissal
/// behaviour with this one.
struct UpdateBannerView: View {
    @EnvironmentObject var updates: UpdateChecker

    var body: some View {
        switch updates.state {
        case .idle:
            EmptyView()

        case .checking:
            banner {
                ProgressView().controlSize(.small)
                Text("Checking for updates…")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

        case .available(let release):
            banner(background: Color.accentColor.opacity(0.12)) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("OpensWith \(displayVersion(release.tagName)) is available.")
                    .font(AppTypography.caption)
                Spacer(minLength: 8)
                Button("View Release") {
                    NSWorkspace.shared.open(release.url)
                }
                .controlSize(.small)
                .font(AppTypography.caption)
                Button {
                    updates.dismissCurrentRelease()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Hide this version")
            }

        case .upToDate:
            banner {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                Text("OpensWith is up to date.")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .task { await autoClear() }

        case .unavailable:
            banner {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.secondary)
                Text("Couldn't check for updates.")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .task { await autoClear() }
        }
    }

    /// Both transient states answer a question asked seconds ago; neither
    /// should still be on screen a minute later. Cancelled automatically if
    /// the state changes first, because `.task` is tied to the view's lifetime.
    private func autoClear() async {
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        guard !Task.isCancelled else { return }
        updates.clearTransientState()
    }

    /// Tags are `v`-prefixed by convention; the banner reads better without it.
    private func displayVersion(_ tag: String) -> String {
        var trimmed = tag
        if let first = trimmed.first, first == "v" || first == "V" {
            trimmed.removeFirst()
        }
        return trimmed.isEmpty ? tag : trimmed
    }

    /// Each case supplies its own trailing `Spacer`, so the one case with
    /// trailing buttons can place it mid-row instead of after them.
    @ViewBuilder
    private func banner<Content: View>(background: Color = .clear,
                                       @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(8)
        .background(background)
    }
}
