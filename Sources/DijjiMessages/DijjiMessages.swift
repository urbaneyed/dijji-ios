import Foundation
import DijjiCore
#if canImport(UIKit)
import UIKit
#endif

/// In-app messages — full UIKit renderer (v1.1).
///
/// Polls `/t/app/inbox` every N seconds while the app is foreground.
/// Each pending message is parsed and handed to MessageHost which picks
/// the right renderer by kind (banner / bottom_sheet / modal). The host
/// queues messages so only one is visible at a time; the rest present
/// in arrival order.
///
/// Messages fire three event types automatically:
///   - `__dijji_message_received` when the SDK pulls it from the inbox
///   - `__dijji_message_clicked` when the user taps the CTA
///   - `__dijji_message_dismissed` with outcome=user_closed/cta_tapped/auto_expired
///
/// All events go through standard track() — they show up in the Dijji
/// dashboard's custom events feed and can be used in funnels.
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
                // Parse — bad rows are skipped, not fatal. The host queues
                // and presents one at a time so we don't spam the user when
                // multiple messages land in the same poll.
                guard let parsed = DijjiMessage.parse(m) else { continue }
                MessageHost.shared.show(parsed)
            }
        }.resume()
    }
}
