import Foundation
import UniformTypeIdentifiers

struct ProbeResult {
    let entries: [HandlerEntry]
    /// Non-nil when the Launch Services database could not be read, in which
    /// case `entries` is empty and this explains why.
    let failureReason: String?
}

enum LaunchServicesProbe {
    static let lsRegisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister"

    static func enumerate() async -> ProbeResult {
        let dump: String
        do {
            dump = try runLSRegisterDump()
        } catch {
            return ProbeResult(entries: [], failureReason: "\(error.localizedDescription)")
        }

        let parsed = LSDumpParser.parse(dump)
        guard !parsed.extensions.isEmpty || !parsed.urlSchemes.isEmpty else {
            return ProbeResult(entries: [], failureReason: "lsregister returned no parseable claims.")
        }
        return ProbeResult(entries: buildEntries(from: parsed), failureReason: nil)
    }

    /// Re-resolves a single extension or URL scheme against the live system.
    ///
    /// Used after a successful change, where a full `enumerate()` would cost
    /// ~3.6s for one row's worth of new information. Delegates to exactly the
    /// same per-entry logic the full probe uses, so the canonical-UTI rule
    /// cannot drift between the two paths.
    static func reresolve(entry: HandlerEntry) -> HandlerEntry {
        switch entry.kind {
        case .fileExtension:
            return extensionEntry(for: entry.displayName)
        case .urlScheme:
            return urlSchemeEntry(for: String(entry.id.dropFirst("url:".count)))
        }
    }

    private static func runLSRegisterDump() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsRegisterPath)
        process.arguments = ["-dump"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileReadUnknown, userInfo: [
                NSLocalizedDescriptionKey:
                    "lsregister exited with status \(process.terminationStatus)."
            ])
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func buildEntries(from parsed: ParseResult) -> [HandlerEntry] {
        var entries = parsed.extensions.map(extensionEntry(for:))
        entries.append(contentsOf: parsed.urlSchemes.map(urlSchemeEntry(for:)))
        return entries.sorted { $0.displayName < $1.displayName }
    }

    /// Resolves an extension's default via the *canonical* system UTI rather than
    /// whichever app-private UTI happened to appear first in the lsregister dump —
    /// several apps declare their own `.pdf`/`.html` variants, and querying Launch
    /// Services with one of those returns the wrong default.
    private static func extensionEntry(for ext: String) -> HandlerEntry {
        let canonicalUTI = UTType(filenameExtension: String(ext.dropFirst()))?.identifier
        let defaultURL = canonicalUTI.flatMap(LaunchServicesLookup.defaultAppURL(forUTI:))
        let altURLs = canonicalUTI.map(LaunchServicesLookup.allAppURLs(forUTI:)) ?? []
        let defaultApp = AppResolver.resolve(url: defaultURL)
        // `LSCopyAllRoleHandlersForContentType` includes the default handler, so
        // subtract it — "other apps that can open it" must mean *other*.
        let alternatives = altURLs
            .compactMap(AppResolver.resolve(url:))
            .filter { $0.bundleID != defaultApp?.bundleID }
        return HandlerEntry(
            id: "ext:\(ext)",
            displayName: ext,
            kind: .fileExtension,
            uti: canonicalUTI,
            defaultApp: defaultApp,
            alternativeApps: alternatives,
            category: Categorizer.categorize(uti: canonicalUTI)
        )
    }

    private static func urlSchemeEntry(for scheme: String) -> HandlerEntry {
        let defaultApp = AppResolver.resolve(
            url: LaunchServicesLookup.defaultAppURL(forURLScheme: scheme))
        // Subtracted against the default for the same reason the extension path
        // does it: "also opens with" must mean *other* apps.
        let alternatives = LaunchServicesLookup.allAppURLs(forURLScheme: scheme)
            .compactMap(AppResolver.resolve(url:))
            .filter { $0.bundleID != defaultApp?.bundleID }
        return HandlerEntry(
            id: "url:\(scheme)",
            displayName: "\(scheme):",
            kind: .urlScheme,
            uti: nil,
            defaultApp: defaultApp,
            alternativeApps: alternatives,
            category: .urlSchemes
        )
    }
}
