import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif
import DijjiCore

/// Server-side bridge for iOS Live Activities.
///
/// The customer's app declares its own `ActivityAttributes`-conforming
/// struct (Apple's framework requires it to be statically typed) and
/// calls `Activity<MyAttrs>.request(...)` to start the activity. Apple
/// returns a `pushToken` that the server can use to push state updates.
///
/// This module's job is to:
///   1. Receive that pushToken from the host app, and
///   2. Ship it to the Dijji server with an opaque `activityId` and
///      JSON-serialised attributes so the dashboard can dispatch
///      updates back to the device.
///
/// The host app then drives state transitions via the dashboard
/// (manual update from /live, or queued from a trigger / journey).
/// The server pushes the new content state via APNs `liveactivity`
/// push type and the OS updates the lock-screen / Dynamic Island
/// rendering automatically.
///
/// Sample integration in the host app:
///
/// ```swift
/// let attrs = OrderTrackingAttributes(orderId: 42, restaurantName: "Baang")
/// let initialState = OrderTrackingAttributes.ContentState(
///     status: "Confirmed", etaMinutes: 35
/// )
/// if let activity = try? Activity<OrderTrackingAttributes>.request(
///     attributes: attrs,
///     contentState: initialState,
///     pushType: .token
/// ) {
///     DijjiLiveActivity.observe(activity, activityId: "order_42")
///     // When the activity ends:
///     // DijjiLiveActivity.end(activityId: "order_42")
/// }
/// ```
public enum DijjiLiveActivity {

    /// Register the activity with Dijji. Call this every time you
    /// receive a new pushToken from `Activity.pushTokenUpdates` —
    /// Apple rotates the token periodically and the latest one is
    /// the only valid target.
    ///
    /// `activityId` is your-app-supplied (typically the canonical
    /// business id like an order number). It's how subsequent updates
    /// route to this activity. Idempotent on (site, activityId) so
    /// re-registering with the same id refreshes the token.
    ///
    /// `attributes` is the static side of the activity (set once,
    /// never changes for the activity's lifetime). Fully serialisable
    /// to JSON — pass strings, numbers, booleans, arrays, dicts.
    public static func register(
        activityId: String,
        pushToken: Data,
        attributes: [String: Any] = [:]
    ) {
        guard !activityId.isEmpty, !pushToken.isEmpty else { return }
        guard let siteKey = Dijji.siteKey, let baseURL = Dijji.apiBase else { return }

        let hex = pushToken.map { String(format: "%02x", $0) }.joined()
        let payload: [String: Any] = [
            "site":        siteKey,
            "visitor_id":  Dijji.visitorId ?? "",
            "activity_id": activityId,
            "push_token":  hex,
            "attributes":  attributes,
        ]
        post("\(baseURL)/t/app/la/register", body: payload)
    }

    /// Inform Dijji the activity has ended on-device. Server marks
    /// the row 'ended' so no further update pushes fire. Safe to call
    /// multiple times — server treats it as idempotent.
    public static func end(activityId: String) {
        guard !activityId.isEmpty else { return }
        guard let siteKey = Dijji.siteKey, let baseURL = Dijji.apiBase else { return }

        let payload: [String: Any] = [
            "site":        siteKey,
            "activity_id": activityId,
        ]
        post("\(baseURL)/t/app/la/end", body: payload)
    }

    #if canImport(ActivityKit) && os(iOS)
    /// Convenience: starts watching `Activity.pushTokenUpdates` and
    /// auto-registers each new token. Call ONCE per activity right
    /// after `Activity.request`. The Task continues until the
    /// activity ends or the task is explicitly cancelled.
    ///
    /// Returns a Task you can cancel manually if you need finer control.
    @available(iOS 16.1, *)
    @discardableResult
    public static func observe<Attrs: ActivityAttributes>(
        _ activity: Activity<Attrs>,
        activityId: String,
        attributes: [String: Any] = [:]
    ) -> Task<Void, Never> {
        return Task {
            for await tokenData in activity.pushTokenUpdates {
                if Task.isCancelled { break }
                DijjiLiveActivity.register(
                    activityId: activityId,
                    pushToken: tokenData,
                    attributes: attributes
                )
            }
        }
    }
    #endif

    // MARK: - Internal HTTP

    /// Fire-and-forget POST. Live Activity register / end are not on
    /// the critical path of any user action, so we don't surface
    /// errors — we just log them and drop the request.
    private static func post(_ urlString: String, body: [String: Any]) {
        guard let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("dijji-ios", forHTTPHeaderField: "X-Dijji-Sdk")
        req.timeoutInterval = 10
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            return
        }
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }
}
