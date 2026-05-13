import XCTest
@testable import DigitalShadow

final class TitleParserTests: XCTestCase {
    func testGitHubPR() {
        let result = TitleParser.parse(title: "Pull Request #42 · myorg/myrepo · GitHub", appName: "Google Chrome")
        XCTAssertTrue(result.contains("GitHub PR #42"))
    }

    func testVSCodeFile() {
        let result = TitleParser.parse(title: "src/login.ts — DigitalShadow", appName: "Visual Studio Code")
        XCTAssertTrue(result.contains("login.ts"))
    }

    func testTerminal() {
        let result = TitleParser.parse(title: "npm run dev — zsh — 80×24", appName: "Terminal")
        XCTAssertTrue(result.contains("终端"))
    }

    func testYouTube() {
        let result = TitleParser.parse(title: "How to Build a Rust CLI — YouTube", appName: "Google Chrome")
        XCTAssertTrue(result.contains("YouTube"))
    }

    func testTwitter() {
        let result = TitleParser.parse(title: "X / home", appName: "Google Chrome")
        XCTAssertTrue(result.contains("X.com"))
    }

    func testGenericReturnsCleanedTitle() {
        let result = TitleParser.parse(title: "Some Random Window", appName: "UnknownApp")
        XCTAssertFalse(result.isEmpty)
    }
}
