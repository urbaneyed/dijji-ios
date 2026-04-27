import Foundation

/// UserDefaults wrapper for SDK persistence. One suite per site_key so
/// multi-site apps (rare but possible — e.g. a parent + child app sharing
/// keychain) don't clobber each other. Survives app updates; clears on
/// app uninstall (iOS purges UserDefaults with the sandbox).
///
/// Things stored here:
///   - visitor_id (persistent person identity)
///   - identified user_id (set via Dijji.identify)
///   - super-properties (set via Dijji.setUserProperty)
///   - opt-out flag
///   - install_fired flag (so app_install fires exactly once)
final class DijjiStorage {
    private let defaults: UserDefaults
    private let prefix: String

    init(siteKey: String) {
        self.prefix = "com.dijji.sdk.\(siteKey)."
        // Use the standard UserDefaults; suiteName-based defaults can fail
        // silently on Mac Catalyst when the suite is missing entitlements.
        // Prefix-keying inside `.standard` is robust everywhere.
        self.defaults = UserDefaults.standard
    }

    var visitorId: String? {
        get { defaults.string(forKey: prefix + "visitor_id") }
        set { defaults.set(newValue, forKey: prefix + "visitor_id") }
    }

    var identifiedUserId: String? {
        get { defaults.string(forKey: prefix + "user_id") }
        set { defaults.set(newValue, forKey: prefix + "user_id") }
    }

    var isOptedOut: Bool {
        get { defaults.bool(forKey: prefix + "opted_out") }
        set { defaults.set(newValue, forKey: prefix + "opted_out") }
    }

    var installFired: Bool {
        get { defaults.bool(forKey: prefix + "install_fired") }
        set { defaults.set(newValue, forKey: prefix + "install_fired") }
    }

    var userProperties: [String: Any] {
        get { defaults.dictionary(forKey: prefix + "user_props") ?? [:] }
    }

    /// Wipe every key written by this storage. Test-only.
    func clearAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    func setUserProperty(key: String, value: Any?) {
        var props = userProperties
        if let v = value {
            // Only store JSON-friendly scalars. Complex types are silently
            // dropped — the alternative is a runtime error months later
            // when the value can't be serialized to /t/app/collect.
            if v is String || v is Int || v is Double || v is Bool || v is NSNumber {
                props[key] = v
            } else {
                DijjiLogger.warn("setUserProperty(\(key)): value type not JSON-serialisable, ignored")
                return
            }
        } else {
            props.removeValue(forKey: key)
        }
        defaults.set(props, forKey: prefix + "user_props")
    }
}
