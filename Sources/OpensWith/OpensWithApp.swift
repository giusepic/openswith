import SwiftUI
import AppKit

@main
struct OpensWithApp: App {
    /// Owned by the App rather than `RootView` so the "Check for Updates…"
    /// command can reach the same instance the banner renders from.
    @StateObject private var updates = UpdateChecker()

    init() {
        // When launched via `swift run` (no .app bundle), the process defaults
        // to a non-UI activation policy and the window never foregrounds.
        // Force regular activation so the window appears and the app shows in
        // the Dock + app switcher.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("OpensWith") {
            RootView()
                .environmentObject(updates)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updates.checkManually() }
                }
                .disabled(updates.state == .checking)
            }
        }
    }
}
