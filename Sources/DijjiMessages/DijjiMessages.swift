import Foundation
import DijjiCore
#if canImport(UIKit)
import UIKit
#endif

/// In-app messages. V1.0-alpha is a stub — only the polling + event firing
/// are implemented. The actual banner / bottom-sheet / modal renderer
/// lands in v1.1 (mirrors the dijji-messages Android module's MessageHost).
///
/// What this DOES today:
///   - Polls /t/app/inbox every 60s while app is foreground
///   - Fires __dijji_message_received for each pending message
///   - Marks messages delivered (the GET endpoint does this server-side)
///
/// What's coming in v1.1:
///   - Native UIKit renderer for kind=banner / bottom_sheet / modal
///   - Message dismiss / CTA handling
///   - Theme support matching the dashboard's site_theme
public enum DijjiMessages {

    private static var pollTimer: Timer?

    /// Start polling the inbox endpoint. Call once after Dijji.initialize.
    /// Idempotent — calling twice doesn't double the poll rate.
    public static func startPolling(every seconds: TimeInterval = 60) {
        DispatchQueue.main.async {
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in
                pollOnce()
            }
            // Fire one immediately rather than waiting `seconds`.
            pollOnce()
        }
    }

    public static func stopPolling() {
        DispatchQueue.main.async {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private static func pollOnce() {
        guard let siteKey = Dijji.siteKey, let visitorId = Dijji.visitorId else { return }
        let base = Dijji.shared?.apiBase ?? "https://dijji.com"
        var comps = URLComponents(string: base + "/t/app/inbox")!
        comps.queryItems = [
            URLQueryItem(name: "site",     value: siteKey),
            URLQueryItem(name: "visitor",  value: visitorId),
            URLQueryItem(name: "platform", value: "ios"),
        ]
        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = obj["messages"] as? [[String: Any]] else { return }
            for m in messages {
                Dijji.track("__dijji_message_received", properties: [
                    "message_id": m["id"] as? String ?? "",
                    "kind": m["kind"] as? String ?? "",
                ])
                // Render hook — v1.1 will instantiate UIKit views here.
            }
        }.resume()
    }
}
