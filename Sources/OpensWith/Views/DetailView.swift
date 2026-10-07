import SwiftUI

struct DetailView: View {
    @EnvironmentObject var store: AppStore
    @State private var showsTechnicalDetails = false

    var body: some View {
        Group {
            if let entry = store.selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header(for: entry)
                        let siblings = store.siblingExtensions(of: entry)
                        if !siblings.isEmpty {
                            sharedTypeNotice(siblings)
                        }
                        currentDefault(for: entry)
                        if store.pendingChangeEntryID != nil {
                            pendingMessage
                        }
                        alternatives(for: entry)
                        outcomeMessage()
                        Divider()
                        technicalDetails(for: entry)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.selectedEntryID) { _ in
            showsTechnicalDetails = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.accentColor)
                .frame(width: 76, height: 76)
                .background(Color.accentColor.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            Text("What opens this type?")
                .font(AppTypography.heading)
            Text("Select a file type or URL scheme to see its default app and alternatives.")
                .font(AppTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(for entry: HandlerEntry) -> some View {
        HStack(spacing: 16) {
            Image(systemName: entry.symbolName)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(entry.category.tint)
                .frame(width: 64, height: 64)
                .background(entry.category.tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.displayName)
                    .font(.system(size: 28, weight: .bold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.typeDescription)
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func sharedTypeNotice(_ siblings: [String]) -> some View {
        // The warning stays ahead of all change actions: UTI siblings move together.
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Also changes \(siblings.joined(separator: ", "))")
                    .font(AppTypography.body.weight(.semibold))
                Text("These extensions share the same file type.")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.16))
        }
        .accessibilityElement(children: .combine)
    }

    private func currentDefault(for entry: HandlerEntry) -> some View {
        let app = entry.defaultApp
        return VStack(alignment: .leading, spacing: 9) {
            sectionHeading("Current default")
            InspectorCard {
                HStack(spacing: 14) {
                    if let app {
                        appIcon(app, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.displayName)
                                .font(AppTypography.appName)
                                .foregroundStyle(app.exists ? .primary : .secondary)
                            Text(app.exists
                                 ? (entry.kind == .urlScheme ? "Opens this URL scheme" : "Opens this file type")
                                 : "Not installed")
                                .font(AppTypography.body)
                                .foregroundStyle(app.exists ? Color.secondary : Color.orange)
                        }
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Not assigned").font(AppTypography.appName)
                            Text("No default app is registered.")
                                .font(AppTypography.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
    }

    private func alternatives(for entry: HandlerEntry) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                sectionHeading("Open with")
                Spacer()
                Text("\(entry.alternativeApps.count.formatted()) \(entry.alternativeApps.count == 1 ? "app" : "apps")")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
            if entry.alternativeApps.isEmpty {
                Text("No alternative apps are registered.")
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
            } else {
                InspectorCard {
                    VStack(spacing: 0) {
                        ForEach(entry.alternativeApps) { app in
                            if app.id != entry.alternativeApps.first?.id {
                                Divider().padding(.leading, 12)
                            }
                            alternativeRow(app, for: entry)
                        }
                    }
                }
            }
        }
    }

    private func alternativeRow(_ app: AppRef, for entry: HandlerEntry) -> some View {
        HStack(spacing: 10) {
            appIcon(app, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(AppTypography.body)
                    .foregroundStyle(app.exists ? .primary : .secondary)
                    .lineLimit(2)
                    .help(app.displayName)
                if !app.exists {
                    Text("Not installed")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Button("Make default") {
                Task { await store.changeDefault(to: app, for: entry) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(AppTypography.caption)
            .fixedSize()
            .disabled(!app.exists || store.pendingChangeEntryID != nil || store.isLoading)
            .accessibilityLabel("Make \(app.displayName) the default for \(entry.displayName)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func appIcon(_ app: AppRef, size: CGFloat) -> some View {
        if app.exists, let url = app.bundleURL {
            AppIcon(url: url, size: size)
        } else {
            Image(systemName: app.exists ? "app" : "exclamationmark.triangle.fill")
                .font(.system(size: size * 0.65))
                .foregroundStyle(app.exists ? Color.secondary : Color.orange)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title).font(AppTypography.sectionHeading)
    }

    private var pendingMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text("Waiting for macOS confirmation…")
                if let pending = store.entries.first(where: { $0.id == store.pendingChangeEntryID }),
                   pending.id != store.selectedEntryID {
                    Text("Changing the default for \(pending.displayName).")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(AppTypography.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func outcomeMessage() -> some View {
        switch store.lastChangeOutcome {
        case .applied(let app):
            Label("Now opens with \(app.displayName).", systemImage: "checkmark.circle.fill")
                .font(AppTypography.secondary)
                .foregroundStyle(.green)
        case .refused:
            Label("macOS didn't apply that change.", systemImage: "exclamationmark.triangle.fill")
                .font(AppTypography.secondary)
                .foregroundStyle(.orange)
        case .failed(let reason):
            Label("Couldn't change the default — \(reason)", systemImage: "exclamationmark.triangle.fill")
                .font(AppTypography.secondary)
                .foregroundStyle(.orange)
        case .declined, .none:
            EmptyView()
        }
    }

    private func technicalDetails(for entry: HandlerEntry) -> some View {
        DisclosureGroup("Technical details", isExpanded: $showsTechnicalDetails) {
            VStack(alignment: .leading, spacing: 12) {
                technicalValue("Kind", entry.kind == .urlScheme ? "URL scheme" : "File extension")
                technicalValue("Category", entry.category.displayName)
                if let uti = entry.uti {
                    technicalValue("Type identifier", uti)
                }
                if let app = entry.defaultApp {
                    technicalValue("Bundle ID", app.bundleID)
                    if let path = app.bundleURL?.path {
                        technicalValue("App path", path)
                    }
                }
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(AppTypography.body)
        .foregroundStyle(.secondary)
    }

    private func technicalValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(AppTypography.caption)
            Text(value)
                .font(AppTypography.technical)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
