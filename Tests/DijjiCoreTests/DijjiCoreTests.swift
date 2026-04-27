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

    func testVisitorIdStableAcrossReinit() {
        // Visitor identity is the load-bearing concept — it must survive
        // a "logout/login" cycle within the same install. We simulate by
        // tearing down the shared instance (NOT clearing storage) and
        // re-initializing — should pick up the same persisted id.
        Dijji.initialize(siteKey: "ws_test123")
        let firstId = Dijji.visitorId!
        Dijji.shared = nil  // accessible because @testable import
        Dijji.initialize(siteKey: "ws_test123")
        XCTAssertEqual(Dijji.visitorId, firstId,
            "visitor_id must survive an SDK re-init within the same install")
    }

    func testSetUserPropertyAccepted() {
        Dijji.initialize(siteKey: "ws_test123")
        // Scalar values should round-trip through UserDefaults via setUserProperty.
        Dijji.setUserProperty("plan", value: "pro")
        Dijji.setUserProperty("seats", value: 5)
        Dijji.setUserProperty("paid", value: true)
        // Wait briefly for the async setter (DijjiClient dispatches to
        // internalQueue). 50ms is plenty for a UserDefaults write.
        let exp = expectation(description: "user props persisted")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        let props = DijjiStorage(siteKey: "ws_test123").userProperties
        XCTAssertEqual(props["plan"] as? String, "pro")
        XCTAssertEqual(props["seats"] as? Int, 5)
        XCTAssertEqual(props["paid"] as? Bool, true)
    }

    func testSetUserPropertyClearsOnNil() {
        Dijji.initialize(siteKey: "ws_test123")
        Dijji.setUserProperty("plan", value: "pro")
        Dijji.setUserProperty("plan", value: nil)
        let exp = expectation(description: "props cleared")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        XCTAssertNil(DijjiStorage(siteKey: "ws_test123").userProperties["plan"])
    }

    func testIdentifyPersists() {
        Dijji.initialize(siteKey: "ws_test123")
        Dijji.identify("user_42")
        let exp = expectation(description: "identify processed")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(DijjiStorage(siteKey: "ws_test123").identifiedUserId, "user_42")
    }

    func testIdentifyEmptyIgnored() {
        Dijji.initialize(siteKey: "ws_test123")
        Dijji.identify("")  // should be a no-op, not store empty string
        let exp = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        XCTAssertNil(DijjiStorage(siteKey: "ws_test123").identifiedUserId)
    }

    func testDeviceContextHasRequiredFields() {
        // The backend's /t/app/install endpoint expects certain fields.
        // Test guards against accidentally dropping one in a refactor.
        let ctx = DeviceContext.snapshot()
        XCTAssertEqual(ctx["sdk_platform"] as? String, "ios")
        XCTAssertEqual(ctx["sdk_version"] as? String, "1.0.0-alpha")
        XCTAssertNotNil(ctx["app_version"])
        XCTAssertNotNil(ctx["bundle_id"])
        XCTAssertNotNil(ctx["timezone"])
        XCTAssertNotNil(ctx["locale"])
    }
}
