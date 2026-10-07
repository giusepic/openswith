import Foundation
import AppKit
import UniformTypeIdentifiers

/// The outcome of asking the system to change a default.
///
/// `declined` exists because macOS reports the user's "keep the current app"
/// choice as NSCocoaErrorDomain 256 "The file couldn't be opened." — a message
/// about nothing that happened. Surfacing it would report a broken app to
/// someone who simply said no.
enum ChangeOutcome: Equatable {
    /// The system confirms the requested app is now the default.
    case applied(AppRef)
    /// The user chose "Keep <current app>" in the OS dialog.
    case declined
    /// The call reported success but the default did not move.
    case refused
    /// A genuine error, carrying the system's own description.
    case failed(reason: String)
}

protocol DefaultsWriting: Sendable {
    func setDefault(app: AppRef, for entry: HandlerEntry) async -> ChangeOutcome
}

/// The three NSWorkspace operations this feature needs, behind a protocol so
/// the outcome-mapping logic can be tested without triggering the OS consent
/// dialog or mutating the developer's real defaults.
protocol WorkspaceWriting: Sendable {
    func setDefaultApplication(at appURL: URL,
                               toOpen type: UTType,
                               completion: @escaping (Error?) -> Void)
    func setDefaultApplication(at appURL: URL,
                               toOpenURLsWithScheme scheme: String,
                               completion: @escaping (Error?) -> Void)
    func currentDefaultBundleID(for entry: HandlerEntry) -> String?
}

struct SystemDefaultsWriter: DefaultsWriting {
    private let workspace: WorkspaceWriting

    init(workspace: WorkspaceWriting = RealWorkspace()) {
        self.workspace = workspace
    }

    func setDefault(app: AppRef, for entry: HandlerEntry) async -> ChangeOutcome {
        guard let appURL = app.bundleURL else {
            return .failed(reason: "That app's location is unknown.")
        }

        // Resolved here, not inside `submit`, so an unusable entry returns
        // `.failed` directly. An earlier version fabricated a CocoaError and
        // round-tripped it through the continuation; that worked, but it meant a
        // one-character slip — `.fileReadUnknown` is 256, the sentinel for "the
        // user declined" — would silently show the user nothing at all.
        let target: WriteTarget
        switch entry.kind {
        case .fileExtension:
            guard let identifier = entry.uti, let type = UTType(identifier) else {
                return .failed(reason: "This entry has no usable content type.")
            }
            target = .contentType(type)

        case .urlScheme:
            // "url:mailto" -> "mailto". Routed by `kind`, never by "is uti nil":
            // every URL scheme entry carries uti == nil by design.
            let scheme = String(entry.id.dropFirst("url:".count))
            guard !scheme.isEmpty else {
                return .failed(reason: "This entry has no usable URL scheme.")
            }
            target = .urlScheme(scheme)
        }

        let error = await submit(app: appURL, to: target)

        if let error = error as NSError? {
            // 256 is how macOS reports "the user kept the existing app".
            if error.domain == NSCocoaErrorDomain && error.code == 256 {
                return .declined
            }
            return .failed(reason: error.localizedDescription)
        }

        // A nil error means the request completed, NOT that the default moved.
        // Verified empirically: writes can report success and change nothing.
        return workspace.currentDefaultBundleID(for: entry) == app.bundleID
            ? .applied(app)
            : .refused
    }

    /// What the system is being asked to bind the app to, already validated.
    private enum WriteTarget {
        case contentType(UTType)
        case urlScheme(String)
    }

    /// Hands the request to the system. `finish` is now only ever called by an
    /// actual workspace callback, so every `Error` reaching `setDefault` is the
    /// system's own.
    private func submit(app appURL: URL, to target: WriteTarget) async -> Error? {
        await withCheckedContinuation { continuation in
            // The OS owns this callback and it blocks on a human answering a
            // dialog. Guard against a double or missing resume rather than let
            // a cosmetic feature trap the process.
            let resumed = ResumeGuard()
            let finish: (Error?) -> Void = { error in
                guard resumed.claim() else { return }
                continuation.resume(returning: error)
            }

            switch target {
            case .contentType(let type):
                workspace.setDefaultApplication(at: appURL, toOpen: type, completion: finish)
            case .urlScheme(let scheme):
                workspace.setDefaultApplication(at: appURL,
                                                toOpenURLsWithScheme: scheme,
                                                completion: finish)
            }
        }
    }
}

/// One-shot latch for continuation resumption.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    /// Returns true exactly once, however many times it is called.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

struct RealWorkspace: WorkspaceWriting {
    func setDefaultApplication(at appURL: URL,
                               toOpen type: UTType,
                               completion: @escaping (Error?) -> Void) {
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type, completion: completion)
    }

    func setDefaultApplication(at appURL: URL,
                               toOpenURLsWithScheme scheme: String,
                               completion: @escaping (Error?) -> Void) {
        NSWorkspace.shared.setDefaultApplication(at: appURL,
                                                 toOpenURLsWithScheme: scheme,
                                                 completion: completion)
    }

    func currentDefaultBundleID(for entry: HandlerEntry) -> String? {
        switch entry.kind {
        case .fileExtension:
            guard let identifier = entry.uti, let type = UTType(identifier) else { return nil }
            return NSWorkspace.shared.urlForApplication(toOpen: type)
                .flatMap { Bundle(url: $0)?.bundleIdentifier }
        case .urlScheme:
            let scheme = String(entry.id.dropFirst("url:".count))
            guard let url = URL(string: "\(scheme)://") else { return nil }
            return NSWorkspace.shared.urlForApplication(toOpen: url)
                .flatMap { Bundle(url: $0)?.bundleIdentifier }
        }
    }
}
