import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Snapshot of device context attached to install events + (when requested)
/// every event. Mirrors the rich-context payload the Android SDK sends so
/// the same dashboard fields populate for both platforms.
///
/// What we DON'T capture:
///   - IDFA — Apple's ATT prompt is a UX cost we don't pay. IDFV (per-app)
///     is sufficient for our needs and doesn't require ATT.
///   - Precise location — Dijji doesn't request location permissions.
///   - Contacts / camera / photos / mic — none of our use cases need them.
enum DeviceContext {

    static func snapshot() -> [String: Any] {
        var ctx: [String: Any] = [:]

        ctx["sdk_platform"] = "ios"
        ctx["sdk_version"]  = "1.5.0-alpha"

        let info = Bundle.main.infoDictionary ?? [:]
        ctx["app_version"]     = info["CFBundleShortVersionString"] as? String ?? "unknown"
        ctx["app_build"]       = info["CFBundleVersion"] as? String ?? "unknown"
        ctx["bundle_id"]       = Bundle.main.bundleIdentifier ?? "unknown"
        ctx["app_name"]        = info["CFBundleName"] as? String ?? "unknown"

        #if canImport(UIKit)
        let dev = UIDevice.current
        ctx["os_version"]      = dev.systemVersion
        ctx["os_name"]         = dev.systemName              // "iOS" / "iPadOS"
        ctx["device_model"]    = deviceModelIdentifier()     // "iPhone15,3"
        ctx["device_id"]       = dev.identifierForVendor?.uuidString ?? ""
        let screen = UIScreen.main
        ctx["screen_width"]    = Int(screen.bounds.width * screen.scale)
        ctx["screen_height"]   = Int(screen.bounds.height * screen.scale)
        ctx["screen_scale"]    = Double(screen.scale)
        let traits = UIScreen.main.traitCollection
        ctx["dark_mode"]       = traits.userInterfaceStyle == .dark
        // Battery monitoring requires opt-in — flip it on, read, flip off
        // (it costs about 1% extra CPU when enabled, no point leaving it).
        let prevMonitoring = dev.isBatteryMonitoringEnabled
        if !prevMonitoring { dev.isBatteryMonitoringEnabled = true }
        ctx["battery_level"]   = Int(max(0, dev.batteryLevel * 100))
        ctx["battery_state"]   = batteryStateString(dev.batteryState)
        if !prevMonitoring { dev.isBatteryMonitoringEnabled = false }
        #endif

        ctx["timezone"]        = TimeZone.current.identifier
        ctx["locale"]          = Locale.current.identifier
        ctx["country"]         = (Locale.current as NSLocale).object(forKey: .countryCode) as? String ?? ""

        // Memory + disk are nice-to-have for debugging crashes that
        // correlate with low-memory / low-disk states.
        var memInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let memOk = withUnsafeMutablePointer(to: &memInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if memOk == KERN_SUCCESS {
            ctx["memory_used_mb"] = Int(memInfo.resident_size / (1024 * 1024))
        }

        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            if let free = attrs[.systemFreeSize] as? NSNumber {
                ctx["disk_free_mb"] = Int(free.int64Value / (1024 * 1024))
            }
        }

        return ctx
    }

    /// Hardware identifier ("iPhone15,3" rather than "iPhone"). Useful for
    /// segmenting crashes by exact hardware. Matches what Android sends as
    /// device_model.
    private static func deviceModelIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let mirror = Mirror(reflecting: sysinfo.machine)
        return mirror.children.compactMap { (_, v) -> String? in
            guard let val = v as? Int8, val != 0 else { return nil }
            return String(UnicodeScalar(UInt8(val)))
        }.joined()
    }

    #if canImport(UIKit)
    private static func batteryStateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown:   return "unknown"
        case .unplugged: return "unplugged"
        case .charging:  return "charging"
        case .full:      return "full"
        @unknown default: return "unknown"
        }
    }
    #endif
}
