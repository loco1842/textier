import Foundation
import Testing
@testable import TextierCore

@Suite("Updates")
struct UpdateTests {
    func version(_ text: String) -> AppVersion { AppVersion(text)! }

    @Test func versionsReadAsTagsAreWritten() {
        #expect(version("v0.2.0").description == "0.2.0")
        #expect(version("1.2").description == "1.2.0")
        #expect(version("0.0.0-dev.7").description == "0.0.0-dev.7")
        #expect(version("1.0.0+build.5").description == "1.0.0")
        for bad in ["", "v", "1.2.3.4", "1.x", "-1.0", "1.0-", "1.0-a..b"] { #expect(AppVersion(bad) == nil, "\(bad)") }
    }

    @Test func versionsCompareAsSemanticVersions() {
        #expect(version("0.1.1") < version("0.2.0"))
        #expect(version("0.9.0") < version("0.10.0"))
        #expect(version("0.2.0-dev.9") < version("0.2.0"))
        #expect(version("0.2.0-dev.2") < version("0.2.0-dev.10"))
        #expect(version("0.2.0-dev.9") < version("0.2.0-rc.1"))
        #expect(version("0.2.0-rc") < version("0.2.0-rc.1"))
        #expect(!(version("v0.2.0") < version("0.2")))
        #expect(version("v0.2.0") == version("0.2"))
    }

    static let release = #"""
    {
      "tag_name": "v0.3.0",
      "name": "textier 0.3.0",
      "draft": false,
      "prerelease": false,
      "html_url": "https://github.com/loco1842/textier/releases/tag/v0.3.0",
      "body": "## What's new\n- Folding",
      "assets": [
        { "name": "textier-0.3.0.dmg", "browser_download_url": "https://github.com/x/textier-0.3.0.dmg" },
        { "name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/x/SHA256SUMS.txt" },
        { "name": "textier-0.3.0.zip", "browser_download_url": "https://github.com/x/textier-0.3.0.zip" }
      ]
    }
    """#

    @Test func aGitHubReleaseIsRead() throws {
        let release = try #require(Release(gitHubJSON: Self.release))
        #expect(release.version == version("0.3.0"))
        #expect(release.tag == "v0.3.0")
        #expect(release.notes == "## What's new\n- Folding")
        #expect(release.page.absoluteString == "https://github.com/loco1842/textier/releases/tag/v0.3.0")
        #expect(release.archive?.name == "textier-0.3.0.zip")
        #expect(release.archive?.url.absoluteString == "https://github.com/x/textier-0.3.0.zip")
        #expect(release.checksums?.absoluteString == "https://github.com/x/SHA256SUMS.txt")
    }

    @Test func draftsPreReleasesAndOtherTagsArentReleases() {
        #expect(Release(gitHubJSON: Self.release.replacingOccurrences(of: #""draft": false"#, with: #""draft": true"#)) == nil)
        #expect(Release(gitHubJSON: Self.release.replacingOccurrences(of: #""prerelease": false"#, with: #""prerelease": true"#)) == nil)
        #expect(Release(gitHubJSON: Self.release.replacingOccurrences(of: "v0.3.0\"", with: "latest\"")) == nil)
        #expect(Release(gitHubJSON: #"{"message": "Not Found"}"#) == nil)
        #expect(Release(gitHubJSON: "not json") == nil)
    }

    @Test func aCheckOffersOnlyANewerVersionNotSkipped() throws {
        let release = try #require(Release(gitHubJSON: Self.release))
        #expect(updateCheck(current: version("0.2.0"), latest: release, skipped: nil) == .available(release))
        #expect(updateCheck(current: version("0.3.0"), latest: release, skipped: nil) == .upToDate)
        #expect(updateCheck(current: version("0.4.0-dev.1"), latest: release, skipped: nil) == .upToDate)
        #expect(updateCheck(current: version("0.2.0"), latest: release, skipped: "0.3.0") == .skipped(release))
        #expect(updateCheck(current: version("0.2.0"), latest: release, skipped: "0.2.5") == .available(release))
    }

    @Test func checksumsAreReadFromShasumsOutput() {
        let hash = String(repeating: "ab", count: 32)
        let sums = "\(String(repeating: "0", count: 64))  textier-0.3.0.dmg\n\(hash.uppercased()) *textier-0.3.0.zip\n"
        #expect(checksum(of: "textier-0.3.0.zip", in: sums) == hash)
        #expect(checksum(of: "textier-0.2.0.zip", in: sums) == nil)
        #expect(checksum(of: "x.zip", in: "short  x.zip") == nil)
    }

    @Test func anAutomaticCheckIsDueDaily() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(isUpdateCheckDue(lastCheck: nil, now: now))
        #expect(!isUpdateCheckDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        #expect(isUpdateCheckDue(lastCheck: now.addingTimeInterval(-86_400), now: now))
        #expect(isUpdateCheckDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }

    @Test func checkForUpdatesIsOnByDefaultAndRoundTrips() throws {
        #expect(try #require(ConfigFile.load(Data(#"{ "patterns": [] }"#.utf8)).config).checkForUpdates)
        let text = try #require(String(data: ConfigFile.encode(.default), encoding: .utf8))
        #expect(text.contains(#""checkForUpdates": true"#))
        var config = Config.default
        config.checkForUpdates = false
        #expect(ConfigFile.load(ConfigFile.encode(config)).config == config)
        let loaded = ConfigFile.load(Data(#"{ "patterns": [], "checkForUpdates": "no" }"#.utf8))
        #expect(loaded.config?.checkForUpdates == true)
        #expect(loaded.warnings.map(\.message) == [#""checkForUpdates" "no" isn't true or false; checking"#])
    }
}
