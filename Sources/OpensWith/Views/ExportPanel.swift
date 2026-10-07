import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Runs the save panel for a CSV export, including the scope control.
///
/// AppKit rather than SwiftUI's `.fileExporter`, for the accessory view: the
/// scope popup has to sit inside the panel, and `.fileExporter` offers no hook
/// for one. Not unit-tested, per the repo's convention for view-layer code —
/// everything decidable lives in `CSVExporter` and `AppStore.entriesForExport`.
@MainActor
enum ExportPanel {

    /// Presents the panel and writes the file. Returns silently when the user
    /// cancels; raises an alert when the write fails.
    static func run(store: AppStore) {
        let scopePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        scopePopUp.addItems(withTitles: ExportScope.allCases.map(\.displayName))
        // Visible is the default: the user filtered the list on purpose.
        scopePopUp.selectItem(at: 0)

        let panel = NSSavePanel()
        panel.title = "Export Defaults"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = defaultFilename()
        panel.accessoryView = accessoryView(with: scopePopUp)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let scope = ExportScope.allCases[scopePopUp.indexOfSelectedItem]
        let data = CSVExporter.data(for: store.entriesForExport(scope: scope))

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            presentFailure(error, url: url)
        }
    }

    /// `OpensWith-defaults-2026-10-05.csv` — sortable, and distinct per day
    /// so successive exports don't silently overwrite each other.
    private static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "OpensWith-defaults-\(formatter.string(from: Date())).csv"
    }

    private static func accessoryView(with popUp: NSPopUpButton) -> NSView {
        let label = NSTextField(labelWithString: "Export:")
        let stack = NSStackView(views: [label, popUp])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        // The panel sizes its accessory view by autolayout; without an explicit
        // container the stack collapses to zero height.
        let container = NSView()
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
        ])
        return container
    }

    /// An alert, deliberately not `store.failureReason`: that banner reports on
    /// the probe and is cleared by the next refresh, so an export error shown
    /// there would both misattribute the failure to the data and vanish on its own.
    private static func presentFailure(_ error: Error, url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't export to “\(url.lastPathComponent)”."
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
