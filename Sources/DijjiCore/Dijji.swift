import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Dijji iOS SDK — public entry point.
///
/// Two-line integration in your `application(_:didFinishLaunchingWithOptions:)`:
///
///     import DijjiCore
///     Dijji.initialize(siteKey: "ws_a647ba153d0911f1b7")
///
/// Everything else is opt-in. Auto-captures app_open / app_background /
/// session lifecycle / install attribution. Custom events via `track`.
/// User properties via `setUserProperty`. Push token registration is in
/// the optional `DijjiPush` module so apps without push don't pull in
/// `UserNotifications` framework references.
public enum Dijji {

    // MARK: - Public state

    /// Shared SDK instance. nil until `initialize` is called. Public
    /// so the optional modules (push / messages) can resolve back to
    /// the same site_key + visitor_id without a separate handshake.
    public internal(set) static var shared: DijjiClient?

    /// Have we successfully initialized? Cheap accessor for callers.
    public static var isInitialized: Bool { shared != nil }

    // MARK: - Lifecycle

    /// Initialize the SDK. Idempotent — calling twice is a no-op (logs a
    /// warning). Pulls visitor_id from UserDefaults or generates a new
    /// UUID on first launch. Hooks lifecycle observers, fires app_open,
    /// schedules the periodic event flush.
    ///
    /// - Parameters:
    ///   - siteKey: Your `ws_*` site key from /app/sites.
    ///   - apiBase: Override for the ingestion host. Default `https://dijji.com`.
    ///              Useful for staging deployments. Customers normally don't touch this.
    ///   - debug:   When true, logs every event + network call to stdout.
    ///              Off by default — production apps shouldn't be chatty.
    public static func initialize(
        siteKey: String,
        apiBase: String = "https://dijji.com",
        debug: Bool = false
    ) {
        if shared != nil {
            DijjiLogger.warn("Dijji.initialize called twice — ignoring second call")
            return
        }
        guard !siteKey.isEmpty else {
            DijjiLogger.warn("Dijji.initialize called with empty siteKey — SDK disabled")
            return
        }
        DijjiLogger.debugEnabled = debug
        let client = DijjiClient(siteKey: siteKey, apiBase: apiBase)
        shared = client
        client.start()
    }

    // MARK: - Custom events

    /// Track a custom event. No-op if the SDK isn't initialized or the
    /// user has opted out. Properties must be JSON-serialisable scalars
    /// (String / Int / Double / Bool / nil); arrays + dictionaries are
    /// flattened by JSONSerialization at flush time.
    public static func track(_ name: String, properties: [String: Any]? = nil) {
        shared?.track(name: name, properties: properties)
    }

    // MARK: - User properties

    /// Set a user property (super-property). Persists to UserDefaults
    /// and attaches to every future event automatically. Pass `nil` to
    /// clear a previously set property.
    public static func setUserProperty(_ key: String, value: Any?) {
        shared?.setUserProperty(key: key, value: value)
    }

    /// Identify the visitor with a stable user_id (e.g. your DB id).
    /// Optional — anonymous visitor_id is generated automatically.
    /// Calling identify merges all prior anonymous events to this id.
    public static func identify(_ userId: String) {
        shared?.identify(userId: userId)
    }

    // MARK: - Privacy

    /// Stop all collection. Clears the local event queue and persists
    /// the opt-out flag — survives app restarts. No traffic until optIn.
    public static func optOut() { shared?.setOptedOut(true) }

    /// Resume collection. New visitor_id is NOT regenerated — the same
    /// person from before opt-out continues with their identity.
    public static func optIn()  { shared?.setOptedOut(false) }

    /// Has the user opted out?
    public static var isOptedOut: Bool { shared?.isOptedOut ?? false }

    // MARK: - Internal accessors used by DijjiPush / DijjiMessages

    /// Visitor identity used by every event. Read-only externally.
    public static var visitorId: String? { shared?.visitorId }

    /// Site key, exposed so optional modules can build their own API
    /// requests without re-injecting it.
    public static var siteKey: String? { shared?.siteKey }

    /// Ingestion base URL (defaults to `https://dijji.com`). Optional
    /// modules read this to build request URLs without the customer
    /// app having to thread it through.
    public static var apiBase: String? { shared?.apiBase }

    /// Test-only reset — clears the shared client + persisted state for
    /// the given site_key. Marked internal so production code can't touch
    /// it; @testable imports in DijjiCoreTests can. Calling this in
    /// production would silently lose visitor identity.
    internal static func _resetForTesting(siteKey: String? = nil) {
        if let s = siteKey {
            DijjiStorage(siteKey: s).clearAll()
        }
        shared = nil
    }
}
