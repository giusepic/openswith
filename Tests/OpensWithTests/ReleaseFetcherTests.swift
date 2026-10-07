import XCTest
@testable import OpensWith

/// The decoder is tested against captured payload shapes; the network call
/// itself gets a single smoke test, mirroring how `LookupSmokeTests` treats
/// the real Launch Services APIs.
final class ReleaseFetcherTests: XCTestCase {

    private func json(_ string: String) -> Data {
        Data(string.utf8)
    }

    // MARK: - Decoding

    /// Field names captured from a real `releases/latest` response. GitHub
    /// returns ~30 keys; decoding only these two means added fields can't
    /// break us, but a *rename* of either would — hence this test.
    func test_decodesTagAndURL() {
        let data = json("""
        {
          "tag_name": "v3.0.20",
          "html_url": "https://github.com/exelban/stats/releases/tag/v3.0.20",
          "name": "v3.0.20",
          "draft": false,
          "prerelease": false
        }
        """)
        let release = GitHubReleaseFetcher.decode(data)
        XCTAssertEqual(release?.tagName, "v3.0.20")
        XCTAssertEqual(release?.url.absoluteString,
                       "https://github.com/exelban/stats/releases/tag/v3.0.20")
    }

    func test_decodeRejectsMissingFields() {
        XCTAssertNil(GitHubReleaseFetcher.decode(json(#"{"tag_name": "v1.0.0"}"#)))
        XCTAssertNil(GitHubReleaseFetcher.decode(json(#"{"html_url": "https://example.com"}"#)))
        XCTAssertNil(GitHubReleaseFetcher.decode(json("{}")))
    }

    func test_decodeRejectsEmptyTag() {
        let data = json(#"{"tag_name": "   ", "html_url": "https://example.com"}"#)
        XCTAssertNil(GitHubReleaseFetcher.decode(data))
    }

    /// GitHub's 404 body is valid JSON, so the decoder — not just the status
    /// check — has to reject it. This is the exact payload the private repo
    /// returns today.
    func test_decodeRejectsNotFoundPayload() {
        let data = json(#"{"message": "Not Found", "status": "404"}"#)
        XCTAssertNil(GitHubReleaseFetcher.decode(data))
    }

    func test_decodeRejectsGarbage() {
        XCTAssertNil(GitHubReleaseFetcher.decode(json("not json at all")))
        XCTAssertNil(GitHubReleaseFetcher.decode(Data()))
    }

    // MARK: - Repository slug

    func test_defaultSlugIsThisRepo() {
        // Guards against the override leaking into a normal test run.
        if ProcessInfo.processInfo.environment["OPENSWITH_UPDATE_REPO"] == nil {
            XCTAssertEqual(GitHubReleaseFetcher.repositorySlug, "giusepic/openswith")
        }
    }

    // MARK: - Smoke

    /// Hits the real API. While this repo is private the endpoint 404s, so nil
    /// is the correct result — and the assertion that matters is that it comes
    /// back as nil rather than throwing or hanging.
    func test_liveFetchOfPrivateRepoIsSilent() async {
        let fetcher = GitHubReleaseFetcher(slug: "giusepic/openswith")
        let release = await fetcher.latestRelease()
        XCTAssertNil(release, "a private repo must degrade to silence")
    }

    /// A slug that cannot resolve must also degrade to nil, never throw.
    func test_liveFetchOfNonsenseSlugIsSilent() async {
        let fetcher = GitHubReleaseFetcher(slug: "giusepic/this-repo-does-not-exist-0000")
        let release = await fetcher.latestRelease()
        XCTAssertNil(release)
    }
}
