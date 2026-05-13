import XCTest
@testable import DigitalShadow

final class VideoCaptionFetcherTests: XCTestCase {
    func testIsVideoURL() {
        let fetcher = VideoCaptionFetcher()
        XCTAssertTrue(fetcher.isVideoURL("https://www.youtube.com/watch?v=abc123"))
        XCTAssertTrue(fetcher.isVideoURL("https://youtu.be/abc123"))
        XCTAssertTrue(fetcher.isVideoURL("https://www.bilibili.com/video/BV1xx411c7mD"))
        XCTAssertFalse(fetcher.isVideoURL("https://github.com"))
    }

    func testExtractYouTubeVideoID() {
        let fetcher = VideoCaptionFetcher()
        XCTAssertEqual(fetcher.extractYTVideoID("https://www.youtube.com/watch?v=abc123"), "abc123")
        XCTAssertEqual(fetcher.extractYTVideoID("https://youtu.be/abc123"), "abc123")
    }

    func testBuildYTDLPCommand() {
        let fetcher = VideoCaptionFetcher()
        let cmd = fetcher.buildCommand(url: "https://www.youtube.com/watch?v=abc123",
                                        outputPath: "/tmp/test_abc123")
        XCTAssertTrue(cmd.contains("yt-dlp"))
        XCTAssertTrue(cmd.contains("abc123"))
        XCTAssertTrue(cmd.contains("--write-auto-subs"))
        XCTAssertTrue(cmd.contains("--sub-format"))
    }
}
