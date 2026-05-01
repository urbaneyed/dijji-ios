import Foundation

/// Parsed in-app message from the /t/app/inbox endpoint.
///
/// The backend returns each message as `{ id, kind, config }` where `kind`
/// drives which renderer takes it (banner / bottom_sheet / modal / hero /
/// nps / reactions / countdown) and `config` carries the type-specific copy
/// + behavior.
public struct DijjiMessage {
    public enum Kind: String {
        case banner       = "banner"
        case bottomSheet  = "bottom_sheet"
        case modal        = "modal"
        case hero         = "hero"
        case nps          = "nps"
        case reactions    = "reactions"
        case countdown    = "countdown"
        case survey       = "survey"
    }

    public let id: String
    public let kind: Kind
    public let title: String?
    public let body: String?
    public let ctaText: String?
    public let ctaUrl: String?
    public let secondaryCtaText: String?
    public let imageUrl: String?
    /// "top" or "bottom" — banners only. Defaults to "top".
    public let position: String?
    /// Hex color or theme name (purple / cyan / emerald / amber / rose /
    /// indigo / slate / mono). The renderer resolves to RGB.
    public let theme: String?
    /// Auto-dismiss after N seconds. Banners default to 8s; sheet/modal
    /// stay until dismissed by the user. 0 / nil = never auto-dismiss.
    public let ttlSeconds: Int

    // NPS / reactions config
    public let question: String?
    public let lowLabel: String?
    public let highLabel: String?
    public let thanks: String?
    public let emojis: [String]?

    // Countdown config — `deadline` accepts ISO-8601, `+24 hours` style
    // relative offsets, or a Unix-seconds number. Resolved to a UTC Date
    // by `parsedDeadline`.
    public let deadline: Any?
    public let endedText: String?

    // Survey config — full raw config bag, since surveys carry a
    // structured questions list + end_screen the static fields above
    // can't represent. SurveyView parses what it needs from this map.
    public let rawConfig: [String: Any]

    /// Parse a single inbox JSON object. Returns nil on missing/bad fields
    /// rather than throwing — one bad message shouldn't kill the queue.
    /// `id` may arrive as String or Int (server stamps numeric ids); both
    /// are accepted and stringified.
    static func parse(_ obj: [String: Any]) -> DijjiMessage? {
        let rawId: String?
        if let s = obj["id"] as? String { rawId = s }
        else if let n = obj["id"] as? NSNumber { rawId = n.stringValue }
        else { rawId = nil }
        guard let id = rawId,
              let kRaw = obj["kind"] as? String
        else { return nil }
        // The server stamps `in_app_*` prefixes; strip + map.
        let normalized = kRaw.hasPrefix("in_app_")
            ? String(kRaw.dropFirst("in_app_".count))
            : kRaw
        guard let kind = Kind(rawValue: normalized) else { return nil }
        let cfg = (obj["config"] as? [String: Any]) ?? [:]
        let emojisRaw = cfg["emojis"] as? [Any]
        let emojis: [String]? = emojisRaw?.compactMap { $0 as? String }.filter { !$0.isEmpty }
        return DijjiMessage(
            id: id,
            kind: kind,
            title:    cfg["title"]    as? String,
            body:     cfg["body"]     as? String,
            ctaText:  cfg["cta_text"] as? String,
            ctaUrl:   cfg["cta_url"]  as? String,
            secondaryCtaText: cfg["secondary_cta_text"] as? String,
            imageUrl: cfg["image_url"] as? String,
            position: cfg["position"] as? String ?? "top",
            theme:    cfg["theme"]    as? String,
            ttlSeconds: (cfg["ttl_seconds"] as? Int) ?? (kind == .banner ? 8 : 0),
            question:  cfg["question"]   as? String,
            lowLabel:  cfg["low_label"]  as? String,
            highLabel: cfg["high_label"] as? String,
            thanks:    cfg["thanks"]     as? String,
            emojis:    emojis,
            deadline:  cfg["deadline"],
            endedText: cfg["ended_text"] as? String,
            rawConfig: cfg
        )
    }

    /// Resolves the `deadline` config value into a UTC Date. Accepts
    /// ISO-8601 strings, `+24 hours` style relative offsets, or
    /// Unix-seconds numbers. Returns nil when unparseable — caller should
    /// drop the countdown rather than render a broken timer.
    public var parsedDeadline: Date? {
        guard let raw = deadline else { return nil }
        if let n = raw as? NSNumber {
            return Date(timeIntervalSince1970: n.doubleValue)
        }
        guard let s = (raw as? String)?.trimmingCharacters(in: .whitespaces),
              !s.isEmpty else { return nil }
        if s.hasPrefix("+") {
            // Match `+N unit(s)` where unit ∈ {second, minute, hour, day, week}.
            let pattern = #"^\+\s*(\d+)\s*(second|minute|hour|day|week)s?$"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = regex.firstMatch(in: s, options: [], range: NSRange(location: 0, length: s.count)) else {
                return nil
            }
            let nRange = Range(m.range(at: 1), in: s)
            let uRange = Range(m.range(at: 2), in: s)
            guard let nR = nRange, let uR = uRange,
                  let n = Double(s[nR]) else { return nil }
            let unit = s[uR].lowercased()
            let secs: TimeInterval
            switch unit {
            case "second": secs = n
            case "minute": secs = n * 60
            case "hour":   secs = n * 3600
            case "day":    secs = n * 86400
            case "week":   secs = n * 604800
            default: return nil
            }
            return Date().addingTimeInterval(secs)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        return isoNoFrac.date(from: s)
    }
}

/// Theme palette mirror of the web tracker's DIJJI_PALETTE. Resolves a
/// theme name (or a hex string) to a UIColor-friendly RGB triplet.
/// Default: purple (#7c3aed) — matches the platform's primary brand color.
enum DijjiTheme {
    static func color(for theme: String?) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        // Direct hex pass-through.
        if let h = theme, h.hasPrefix("#"), let rgb = hexToRgb(h) {
            return rgb
        }
        switch theme ?? "" {
        case "cyan":    return (0.03, 0.57, 0.70)   // #0891b2
        case "emerald": return (0.02, 0.59, 0.41)   // #059669
        case "green":   return (0.02, 0.59, 0.41)   // #059669
        case "amber":   return (0.85, 0.46, 0.02)   // #d97706
        case "rose":    return (0.88, 0.11, 0.28)   // #e11d48
        case "indigo":  return (0.31, 0.27, 0.90)   // #4f46e5
        case "slate":   return (0.28, 0.33, 0.41)   // #475569
        case "mono":    return (0.09, 0.09, 0.11)   // #18181b
        case "purple":  fallthrough
        default:        return (0.49, 0.23, 0.93)   // #7c3aed
        }
    }

    private static func hexToRgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat)? {
        var s = hex; s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (CGFloat((v >> 16) & 0xFF) / 255,
                CGFloat((v >>  8) & 0xFF) / 255,
                CGFloat( v        & 0xFF) / 255)
    }
}

#if canImport(UIKit)
import UIKit

/// Tiny built-in image loader — fetches via URLSession on a background
/// queue, decodes to UIImage, posts result back to main. Fail-soft: any
/// failure leaves the placeholder background untouched. No third-party
/// dependency.
enum DijjiImageLoader {
    static func load(_ urlString: String?, into view: UIImageView) {
        guard let s = urlString, let url = URL(string: s) else { return }
        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let data = data,
                  let resp = response as? HTTPURLResponse,
                  (200..<300).contains(resp.statusCode),
                  let img = UIImage(data: data) else { return }
            DispatchQueue.main.async { [weak view] in
                view?.image = img
            }
        }.resume()
    }
}
#endif
