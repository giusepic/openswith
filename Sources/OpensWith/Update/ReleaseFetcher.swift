import Foundation

/// A published release, reduced to the two fields this app acts on.
struct Release: Equatable {
    /// The git tag, as GitHub reports it — usually `v`-prefixed.
    let tagName: String
    /// The human-facing release page, opened in the user's browser.
    let url: URL
}

/// The seam. `UpdateChecker` talks to this, never to `URLSession`, so its
/// state machine is testable without a network — matching how `AppStore`
/// injects its probe and writer.
protocol ReleaseFetching: Sendable {
    /// Returns the latest release, or nil if there isn't one *or* it couldn't
    /// be determined. Deliberately not `throws`: see `GitHubReleaseFetcher`.
    func latestRelease() async -> Release?
}

/// Reads the latest release from the GitHub REST API.
///
/// **Never throws, never surfaces an error.** Offline, rate-limited (403),
/// private-or-missing repo (404), malformed JSON and timeouts all return nil,
/// because they are indistinguishable from the user's point of view and the
/// only correct response to every one of them is to say nothing. An update
/// checker that shows an error banner to someone on a plane is worse than one
/// that stays quiet.
///
/// While the repo is private this endpoint returns 404 unauthenticated, so the
/// nil path is the normal path until it goes public. The success path can be
/// exercised ahead of that by pointing `OPENSWITH_UPDATE_REPO` at any public
/// repo — see `repositorySlug`.
struct GitHubReleaseFetcher: ReleaseFetching {

    /// `owner/name`. Overridable via `OPENSWITH_UPDATE_REPO` so the happy path
    /// can be verified against a public repo before this one is published:
    ///
    /// ```
    /// OPENSWITH_UPDATE_REPO=sindresorhus/Plash open dist/OpensWith.app
    /// ```
    static var repositorySlug: String {
        let override = ProcessInfo.processInfo.environment["OPENSWITH_UPDATE_REPO"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty { return override }
        return "giusepic/openswith"
    }

    private let slug: String
    private let session: URLSession

    init(slug: String = GitHubReleaseFetcher.repositorySlug,
         session: URLSession = .shared) {
        self.slug = slug
        self.session = session
    }

    func latestRelease() async -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(slug)/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        // Pins the response shape; without it GitHub may serve a future default.
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("OpensWith", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200
        else { return nil }

        return Self.decode(data)
    }

    /// Split out from the request so it can be unit-tested against captured
    /// payloads without a network round trip.
    static func decode(_ data: Data) -> Release? {
        struct Payload: Decodable {
            let tagName: String?
            let htmlURL: String?

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
            }
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let tag = payload.tagName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tag.isEmpty,
              let link = payload.htmlURL,
              let url = URL(string: link)
        else { return nil }

        return Release(tagName: tag, url: url)
    }
}
