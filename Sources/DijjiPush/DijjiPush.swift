import Foundation
import DijjiCore
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Push notification helper. Apps that don't use push don't need to
/// import DijjiPush at all — keeps DijjiCore free of a hard dependency
/// on UserNotifications.
///
/// Two integration points in your app:
///
///   1. After requesting permission, register the device token:
///      `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
///      → call `DijjiPush.registerToken(deviceToken)`
///
///   2. When notifications arrive, claim Dijji-originated ones:
///      `userNotificationCenter(_:didReceive:withCompletionHandler:)`
///      → call `DijjiPush.handleNotification(response)` first; if it
///         returns true, Dijji has dispatched the deep link and fired
///         push_opened — you can call your own handler if you want or
///         just call the completion handler.
public enum DijjiPush {

    /// Register an APNs device token with the Dijji backend.
    ///
    /// Call from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// Idempotent — registering the same token twice is a no-op server-side.
    public static func registerToken(_ token: Data) {
        Dijji.shared?.registerPushToken(token)
    }

    /// Process a push tap. Returns true if the notification was a
    /// Dijji-originated push (`userInfo["dijji"] == "1"`) — meaning we
    /// fired `push_opened` and routed the `deep_link`. Returns false
    /// otherwise so your app's existing handler can take over.
    @discardableResult
    public static func handleNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard userInfo["dijji"] as? String == "1" else { return false }
        let pushId = userInfo["push_id"] as? String ?? ""
        let triggerId = userInfo["trigger_id"] as? String ?? ""
        let deepLink = userInfo["deep_link"] as? String

        // Fire the open event so the dashboard's push-open metric updates.
        Dijji.track("push_opened", properties: [
            "push_id": pushId,
            "trigger_id": triggerId,
            "deep_link": deepLink ?? "",
        ])

        // Route the deep link if present. Use UIApplication.open so the
        // host app's URL handling (scenes / SwiftUI / UIKit) catches it.
        #if canImport(UIKit)
        if let raw = deepLink, let url = URL(string: raw) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        #endif
        return true
    }

    /// Convenience overload: pass the full UNNotificationResponse from
    /// `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
    #if canImport(UserNotifications)
    @discardableResult
    public static func handleNotification(_ response: UNNotificationResponse) -> Bool {
        return handleNotification(response.notification.request.content.userInfo)
    }
    #endif

    /// Fire `push_received` when a Dijji push lands while the app is in
    /// foreground (or a silent push wakes the process). Call from
    /// `userNotificationCenter(_:willPresent:withCompletionHandler:)` for
    /// foreground reception, or from the `didReceiveRemoteNotification`
    /// handler for silent / background pushes.
    public static func recordReceived(_ userInfo: [AnyHashable: Any]) {
        guard userInfo["dijji"] as? String == "1" else { return }
        Dijji.track("push_received", properties: [
            "push_id": userInfo["push_id"] as? String ?? "",
            "trigger_id": userInfo["trigger_id"] as? String ?? "",
        ])
    }
}
