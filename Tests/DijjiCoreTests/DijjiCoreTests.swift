import XCTest
@testable import DijjiCore

/// Smoke tests — none of these exercise UIKit / network so they run
/// fine on macOS via `swift test`. The full suite (lifecycle hooks,
/// push round-trip) needs an iOS simulator and runs via Xcode.
final class DijjiCoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // The shared static SDK instance + UserDefaults state both need to
        // be cleared between tests since XCTest doesn't isolate static
        // singletons. Each test starts from a known-zero state.
        Dijji._resetForTesting(siteKey: "ws_test123")
    }

    override func tearDown() {
        Dijji._resetForTesting(siteKey: "ws_test123")
        super.tearDown()
    }

    func testInitializeSetsShared() {
        XCTAssertNil(Dijji.shared)
        Dijji.initialize(siteKey: "ws_test123")
        XCTAssertNotNil(Dijji.shared)
        XCTAssertEqual(Dijji.siteKey, "ws_test123")
        XCTAssertNotNil(Dijji.visitorId)
        XCTAssertTrue(Dijji.visitorId!.hasPrefix("u-"))
    }

    func testInitializeIdempotent() {
        Dijji.initialize(siteKey: "ws_test123")
        let firstId = Dijji.visitorId
        Dijji.initialize(siteKey: "ws_test123")  // second call should be ignored
        XCTAssertEqual(Dijji.visitorId, firstId)
    }

    func testEmptySiteKeyIgnored() {
        Dijji.initialize(siteKey: "")
        XCTAssertNil(Dijji.shared)
    }

    func testOptOutPersists() {
        Dijji.initialize(siteKey: "ws_test123")
        XCTAssertFalse(Dijji.isOptedOut)
        Dijji.optOut()
        XCTAssertTrue(Dijji.isOptedOut)
        Dijji.optIn()
        XCTAssertFalse(Dijji.isOptedOut)
    }

    func testTrackBeforeInitIsNoop() {
        // Should not crash, just silently do nothing.
        Dijji.track("foo", properties: ["bar": 1])
    }
}
