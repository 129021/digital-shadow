import XCTest
@testable import DigitalShadow

final class AppClassifierTests: XCTestCase {
    func testBuiltInMapping() {
        let classifier = AppClassifier()
        XCTAssertEqual(classifier.classify(bundleId: "com.google.Chrome"), .browser)
        XCTAssertEqual(classifier.classify(bundleId: "com.microsoft.VSCode"), .editor)
        XCTAssertEqual(classifier.classify(bundleId: "com.tinyspeck.slackmacgap"), .communication)
    }

    func testUnknownBundleReturnsUnknown() {
        let classifier = AppClassifier()
        XCTAssertEqual(classifier.classify(bundleId: "com.some.random.app"), .unknown)
    }

    func testIsBrowser() {
        let classifier = AppClassifier()
        XCTAssertTrue(classifier.isBrowser(bundleId: "com.google.Chrome"))
        XCTAssertFalse(classifier.isBrowser(bundleId: "com.microsoft.VSCode"))
    }
}
