import Foundation
import CoreServices
import AppKit

enum LaunchServicesLookup {
    static func defaultAppURL(forUTI uti: String) -> URL? {
        guard let unmanaged = LSCopyDefaultApplicationURLForContentType(
            uti as CFString, .all, nil) else { return nil }
        return unmanaged.takeRetainedValue() as URL
    }

    static func allAppURLs(forUTI uti: String) -> [URL] {
        guard let unmanaged = LSCopyAllRoleHandlersForContentType(
            uti as CFString, .all) else { return [] }
        let bundleIDs = unmanaged.takeRetainedValue() as? [String] ?? []
        return bundleIDs.compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
    }

    /// Apps that can open this URL scheme.
    ///
    /// Uses the modern `NSWorkspace` API rather than the deprecated
    /// `LSCopyAllHandlersForURLScheme`. Measured at 0.009s across all 198
    /// schemes on a real machine, so it is free to call during the probe.
    static func allAppURLs(forURLScheme scheme: String) -> [URL] {
        guard let url = URL(string: "\(scheme)://") else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    /// The default app for a URL scheme.
    ///
    /// Uses `NSWorkspace` rather than `LSCopyDefaultApplicationURLForURL(_:.viewer:_:)`,
    /// which filters on the viewer role and returns nil for ~60 of ~200 schemes
    /// on a real machine (`tel:`, `facetime:` and friends) that the system does
    /// in fact have a handler for.
    ///
    /// This must stay the same API `SystemDefaultsWriter` verifies a write with.
    /// When the two disagreed, a change could report "Now opens with X" while
    /// the row still read "Not assigned" — and the snapshot persisted the
    /// contradiction. Pinned by
    /// `LookupSmokeTests.test_schemeReadPathAgreesWithWriteVerification`.
    static func defaultAppURL(forURLScheme scheme: String) -> URL? {
        guard let url = URL(string: "\(scheme)://") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: url)
    }
}
