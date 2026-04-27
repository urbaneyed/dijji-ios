import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The actual SDK instance — held by `Dijji.shared`. This split lets us
/// keep the public surface in `Dijji` minimal + namespaced while the
/// stateful parts live here. All public methods are thread-safe.
public final class DijjiClient {

    // MARK: - Identity

    public let siteKey: String
    public let apiBase: String
    public let visitorId: String

    // MARK: - State

    private let storage: DijjiStorage
    private let queue: EventQueue
    private let api: Api
    private let lifecycle: Lifecycle
    private let crashHandler: CrashHandler
    private var sessionId: String
    private var sessionStartedAt: Date

    // Serial queue for all SDK mutations — keeps the event buffer thread-safe
    // without needing locks scattered across methods. Event tracking from any
    // thread is safe.
    private let internalQueue = DispatchQueue(label: "com.dijji.sdk.internal")

    init(siteKey: String, apiBase: String) {
        self.siteKey  = siteKey
        self.apiBase  = apiBase
        self.storage  = DijjiStorage(siteKey: siteKey)

        // Visitor identity — generated on first launch, persisted forever.
        // Survives app deletion only if iOS Keychain is later wired in;
        // current scheme uses UserDefaults which clears on uninstall.
        if let existing = self.storage.visitorId {
            self.visitorId = existing
        } else {
            let newId = "u-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            self.storage.visitorId = newId
            self.visitorId = newId
        }

        self.api = Api(baseURL: apiBase, siteKey: siteKey)
        self.queue = EventQueue(api: api, visitorId: visitorId)
        self.lifecycle = Lifecycle()
        self.crashHandler = CrashHandler(api: api, visitorId: visitorId)
        self.sessionId = "s-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
        self.sessionStartedAt = Date()
    }

    // MARK: - Bootstrap

    /// Wire up notification observers, fire any deferred install/open
    /// events, install crash handler. Called once from `Dijji.initialize`.
    func start() {
        if storage.isOptedOut {
            DijjiLogger.debug("opted out — start() is a no-op")
            return
        }
        crashHandler.install()
        lifecycle.onForeground = { [weak self] in self?.handleForeground() }
        lifecycle.onBackground = { [weak self] in self?.handleBackground() }
        lifecycle.attach()

        // First-ever-launch detection — fires app_install once, never again.
        if !storage.installFired {
            track(name: "app_install", properties: nil, includeContext: true)
            sendInstall()
            storage.installFired = true
        }
        track(name: "app_open", properties: nil)
        track(name: "session_start", properties: ["session_id": sessionId])

        // Periodic flush + on-background flush. 30s feels like a sane balance
        // between battery friendliness and "events feel live in the dashboard".
        queue.startPeriodicFlush(every: 30)
        DijjiLogger.debug("Dijji started — visitor \(visitorId), session \(sessionId)")
    }

    // MARK: - Public mutations

    func track(name: String, properties: [String: Any]?) {
        track(name: name, properties: properties, includeContext: false)
    }

    private func track(name: String, properties: [String: Any]?, includeContext: Bool) {
        if storage.isOptedOut { return }
        guard !name.isEmpty else { return }
        internalQueue.async {
            var props = properties ?? [:]
            // Stamp super-properties on every event so the backend doesn't
            // need a separate identify call to enrich.
            for (k, v) in self.storage.userProperties { props[k] = v }
            if let userId = self.storage.identifiedUserId { props["user_id"] = userId }
            props["session_id"] = self.sessionId
            if includeContext {
                for (k, v) in DeviceContext.snapshot() { props[k] = v }
            }
            self.queue.enqueue(name: name, properties: props)
        }
    }

    func setUserProperty(key: String, value: Any?) {
        internalQueue.async { self.storage.setUserProperty(key: key, value: value) }
    }

    func identify(userId: String) {
        guard !userId.isEmpty else { return }
        internalQueue.async {
            self.storage.identifiedUserId = userId
            // Fire an identify event so the backend can stitch — anonymous
            // visitor_id stays the same, but events from now on carry user_id.
            self.queue.enqueue(name: "identify", properties: ["user_id": userId])
        }
    }

    func setOptedOut(_ optedOut: Bool) {
        internalQueue.async {
            self.storage.isOptedOut = optedOut
            if optedOut {
                self.queue.clearPending()
                self.lifecycle.detach()
                DijjiLogger.debug("opted out — collection paused")
            } else {
                self.lifecycle.attach()
                self.queue.startPeriodicFlush(every: 30)
                DijjiLogger.debug("opted in — collection resumed")
            }
        }
    }

    var isOptedOut: Bool { storage.isOptedOut }

    // MARK: - Push (called from optional DijjiPush module via Dijji.shared)

    /// Register an APNs device token. Called from the host app's
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
    /// (via `DijjiPush.registerToken(_:)`).
    public func registerPushToken(_ token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        DijjiLogger.debug("push token registered: \(hex.prefix(8))…")
        api.post(path: "/t/app/token", body: [
            "site": siteKey,
            "visitor_id": visitorId,
            "token": hex,
            "platform": "ios",
        ], onComplete: { _ in })
    }

    // MARK: - Lifecycle handlers

    private func handleForeground() {
        // 30 minutes of background = new session. Matches the engagement
        // dedup window used elsewhere in Dijji.
        if Date().timeIntervalSince(sessionStartedAt) > 30 * 60 {
            sessionId = "s-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
            sessionStartedAt = Date()
        }
        track(name: "app_open", properties: nil)
    }

    private func handleBackground() {
        let duration = Int(Date().timeIntervalSince(sessionStartedAt))
        track(name: "app_background", properties: ["duration_seconds": duration])
        // Force flush so the session ends with all its events shipped.
        queue.flushNow()
    }

    private func sendInstall() {
        var ctx = DeviceContext.snapshot()
        ctx["site"] = siteKey
        ctx["visitor_id"] = visitorId
        ctx["platform"] = "ios"
        api.post(path: "/t/app/install", body: ctx, onComplete: { _ in })
    }
}
