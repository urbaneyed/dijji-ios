import XCTest
@testable import DijjiMessages

/// Pure-data tests for the inbox JSON parser + theme resolver. No UIKit,
/// no UI — both run on macOS via `swift test`. Renderer integration tests
/// (BannerView showing on a host VC, drag-to-dismiss, etc.) need an
/// iOS Simulator and live in a separate target later.
final class MessageTests: XCTestCase {

    func testParseFullBanner() {
        let raw: [String: Any] = [
            "id": "msg_42",
            "kind": "banner",
            "config": [
                "title": "Welcome back",
                "body": "We picked 3 jobs for you",
                "cta_text": "See them",
                "cta_url": "/jobs",
                "position": "top",
                "theme": "purple",
                "ttl_seconds": 12,
            ],
        ]
        let m = DijjiMessage.parse(raw)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.id, "msg_42")
        XCTAssertEqual(m?.kind, .banner)
        XCTAssertEqual(m?.title, "Welcome back")
        XCTAssertEqual(m?.body, "We picked 3 jobs for you")
        XCTAssertEqual(m?.ctaText, "See them")
        XCTAssertEqual(m?.ctaUrl, "/jobs")
        XCTAssertEqual(m?.position, "top")
        XCTAssertEqual(m?.theme, "purple")
        XCTAssertEqual(m?.ttlSeconds, 12)
    }

    func testParseMinimalSheet() {
        // Sheet without optional fields — still valid, just sparse.
        let raw: [String: Any] = ["id": "m1", "kind": "bottom_sheet", "config": ["body": "Hi"]]
        let m = DijjiMessage.parse(raw)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.kind, .bottomSheet)
        XCTAssertEqual(m?.body, "Hi")
        XCTAssertNil(m?.title)
        XCTAssertNil(m?.ctaUrl)
        // Default ttl: 0 for non-banners (stays until user dismisses)
        XCTAssertEqual(m?.ttlSeconds, 0)
    }

    func testParseDefaultBannerTtl() {
        // Banner without ttl_seconds defaults to 8s
        let raw: [String: Any] = ["id": "m1", "kind": "banner", "config": ["body": "Hi"]]
        let m = DijjiMessage.parse(raw)
        XCTAssertEqual(m?.ttlSeconds, 8)
    }

    func testParseModalKind() {
        let raw: [String: Any] = ["id": "m1", "kind": "modal", "config": [:]]
        XCTAssertEqual(DijjiMessage.parse(raw)?.kind, .modal)
    }

    func testParseRejectsMissingId() {
        XCTAssertNil(DijjiMessage.parse(["kind": "banner", "config": [:]]))
    }

    func testParseRejectsBadKind() {
        // Unknown kind values fail parse — the renderer can't choose
        // which view to instantiate, so failing closed is right.
        XCTAssertNil(DijjiMessage.parse(["id": "x", "kind": "carousel", "config": [:]]))
    }

    func testParseRejectsEmpty() {
        XCTAssertNil(DijjiMessage.parse([:]))
    }

    func testThemeResolution() {
        // Named themes resolve to their hex values
        let purple = DijjiTheme.color(for: "purple")
        XCTAssertEqual(round(purple.red * 100) / 100, 0.49)

        let cyan = DijjiTheme.color(for: "cyan")
        XCTAssertEqual(round(cyan.green * 100) / 100, 0.57)

        // Direct hex pass-through
        let direct = DijjiTheme.color(for: "#ff0000")
        XCTAssertEqual(direct.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(direct.green, 0, accuracy: 0.01)

        // Unknown theme falls back to purple
        let unknown = DijjiTheme.color(for: "fuchsia-glow")
        XCTAssertEqual(round(unknown.red * 100) / 100, 0.49)

        // nil also defaults to purple
        let nilTheme = DijjiTheme.color(for: nil)
        XCTAssertEqual(round(nilTheme.red * 100) / 100, 0.49)
    }
}
