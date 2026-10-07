import Foundation
import AppKit

enum AppResolver {
    static func resolve(url: URL?) -> AppRef? {
        guard let url else { return nil }
        let exists = FileManager.default.fileExists(atPath: url.path)
        let bundle = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier ?? url.lastPathComponent
        let name = (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppRef(bundleID: bundleID, displayName: name, bundleURL: url, exists: exists)
    }
}
