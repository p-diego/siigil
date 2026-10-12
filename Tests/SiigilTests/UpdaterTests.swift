import Foundation
import Testing
@testable import Siigil

// Numeri, non testo: 0.10 viene dopo 0.9. La "v" dei tag non conta.
@Test func newerComparesNumbersNotText() {
    #expect(isNewer("0.10", than: "0.9"))
    #expect(isNewer("0.12.1", than: "0.12"))
    #expect(isNewer("v0.13", than: "0.12"))
    #expect(isNewer("0.13", than: "v0.12"))
}

@Test func sameOrOlderIsNotNewer() {
    #expect(!isNewer("0.12", than: "0.12"))
    #expect(!isNewer("v0.12", than: "0.12"))
    #expect(!isNewer("0.9", than: "0.10"))
    #expect(!isNewer("0.11", than: "0.12"))
}

// Il JSON di releases/latest ridotto ai campi che servono.
private func releaseJSON(tag: String, assets: [String]) -> Data {
    let list = assets.map { #"{"name": "\#($0)", "browser_download_url": "https://github.com/p-diego/siigil/releases/download/\#(tag)/\#($0)"}"# }
    return Data(#"{"tag_name": "\#(tag)", "html_url": "https://github.com/p-diego/siigil/releases/tag/\#(tag)", "assets": [\#(list.joined(separator: ","))]}"#.utf8)
}

@Test func parsesTheZipAmongTheAssets() {
    let r = parseRelease(releaseJSON(tag: "v0.13", assets: ["Siigil-0.13.dmg", "Siigil-0.13.zip"]))
    #expect(r == Release(version: "0.13",
                         page: URL(string: "https://github.com/p-diego/siigil/releases/tag/v0.13")!,
                         zip: URL(string: "https://github.com/p-diego/siigil/releases/download/v0.13/Siigil-0.13.zip")!))
}

// Senza lo zip della sua versione (solo il DMG, o lo zip di un'altra) la release non serve.
@Test func releaseWithoutItsZipIsNil() {
    #expect(parseRelease(releaseJSON(tag: "v0.13", assets: ["Siigil-0.13.dmg"])) == nil)
    #expect(parseRelease(releaseJSON(tag: "v0.13", assets: ["Siigil-0.12.zip"])) == nil)
}

// Rotto, o la risposta di GitHub quando il repo non ha ancora release (404).
@Test func brokenJSONOrGitHubErrorIsNil() {
    #expect(parseRelease(Data("{".utf8)) == nil)
    #expect(parseRelease(Data(#"{"message": "Not Found", "documentation_url": "https://docs.github.com/rest"}"#.utf8)) == nil)
}

@Test func dueImmediatelyThenAfterADayOrAnHour() {
    let now = Date()
    #expect(isDue(last: nil, succeeded: false, now: now))
    #expect(!isDue(last: now.addingTimeInterval(-23 * 3600), succeeded: true, now: now))
    #expect(isDue(last: now.addingTimeInterval(-24 * 3600), succeeded: true, now: now))
    #expect(!isDue(last: now.addingTimeInterval(-59 * 60), succeeded: false, now: now))
    #expect(isDue(last: now.addingTimeInterval(-3600), succeeded: false, now: now))
}

@Test func relaunchWaitsForThisProcessAndSurvivesSpaces() {
    #expect(relaunchArguments(pid: 42, app: "/Users/x/My Apps/Siigil.app") ==
            ["-c", "while kill -0 42 2>/dev/null; do sleep 0.1; done; open \"$0\"", "/Users/x/My Apps/Siigil.app"])
}
