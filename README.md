# Dijji iOS SDK

> Analytics, push, in-app messages, and crash capture for iOS apps. From one `init()` call.
> Mirror of the [Dijji Android SDK](https://github.com/urbaneyed/dijji-android).
> Status: **v1.0.0-alpha** — backend live, SDK in active development.

## Quick start

### Swift Package Manager

In Xcode → **File → Add Package Dependencies**, then paste:

```
https://github.com/urbaneyed/dijji-ios
```

Pick the modules you want. `DijjiCore` is required; `DijjiPush` and `DijjiMessages` are optional.

### Two-line integration

In your `AppDelegate` (or `App` body for SwiftUI):

```swift
import DijjiCore

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey : Any]?) -> Bool {
        Dijji.initialize(siteKey: "ws_a647ba153d0911f1b7")
        return true
    }
}
```

That's it. The SDK auto-captures `app_open`, `app_background`, `session_start/end`, `app_install` (once, on first launch), and starts collecting rich device context.

## Custom events

```swift
Dijji.track("checkout_completed", properties: [
    "amount_cents": 1999,
    "currency": "USD",
    "items": 3
])
```

## User properties

Persistent super-properties — attached to every future event.

```swift
Dijji.setUserProperty("plan", value: "pro")
Dijji.setUserProperty("signup_date", value: "2026-04-28")
Dijji.identify("user_42")
```

## Push notifications (`DijjiPush`)

After requesting authorization with `UNUserNotificationCenter`, register the device token:

```swift
import DijjiPush

func application(_ app: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    DijjiPush.registerToken(token)
}
```

Handle pushes that originated from Dijji:

```swift
func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completionHandler: @escaping () -> Void) {
    // If Dijji handles it (fires push_opened, routes deep_link), this returns true.
    let handled = DijjiPush.handleNotification(response)
    completionHandler()
}
```

The host app is responsible for setting up APNs entitlements + the Push Notifications capability. Configure your APNs auth key (.p8 + key_id + team_id + bundle_id) at `https://dijji.com/app/sites/{your_site_key}/mobile`.

## In-app messages (`DijjiMessages`)

`v1.0-alpha` ships polling + event firing only. The native UIKit renderer (banner / bottom-sheet / modal) lands in v1.1.

```swift
import DijjiMessages
DijjiMessages.startPolling()  // call once after Dijji.initialize
```

## Privacy

- **No IDFA.** Only IDFV (per-app, requires no ATT prompt).
- **No location, contacts, photos, mic, or camera.**
- **Opt-out at runtime.** `Dijji.optOut()` clears local state and stops all collection.
- **TLS only.** All traffic to `https://dijji.com` (HSTS preloaded).

## Building from source

```bash
swift build           # builds for the host (macOS) — non-UIKit parts only
swift test            # runs DijjiCoreTests on macOS
xcodebuild -scheme DijjiCore -destination 'platform=iOS Simulator,name=iPhone 15'   # full iOS build
```

## License

Apache 2.0. See [LICENSE](LICENSE).

## Roadmap

| Version | Scope | Status |
|---|---|---|
| v1.0-alpha | Two-line init, lifecycle auto-capture, custom events, user props, NSException crash capture, push token registration, deep-link routing | **Active development** |
| v1.1 | Native in-app message renderer (banner / sheet / modal) | Planned |
| v1.2 | POSIX signal crash handler &middot; Mach exception port handler for pure-Swift crashes | Planned |
| v1.3 | Live Activities (iOS 16+) &middot; Notification Service Extension for rich pushes | Q4 2026 |
| v2.0 | SwiftUI-native message components &middot; Core Data offline queue | 2027 |
