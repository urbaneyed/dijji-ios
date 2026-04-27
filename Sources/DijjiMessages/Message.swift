import Foundation

/// Parsed in-app message from the /t/app/inbox endpoint.
///
/// The backend returns each message as `{ id, kind, config }` where `kind`
/// drives which renderer takes it (banner / bottom_sheet / modal) and
/// `config` carries the type-specific copy + behavior (title, body,
/// cta_text, cta_url, theme, position).
public struct DijjiMessage {
    public enum Kind: String {
        case banner       = "banner"
        case bottomSheet  = "bottom_sheet"
        case modal        = "modal"
    }

    public let id: String
    public let kind: Kind
    public let title: String?
    public let body: String?
    public let ctaText: String?
    public let ctaUrl: String?
    /// "top" or "bottom" — banners only. Defaults to "top".
    public let position: String?
    /// Hex color or theme name (purple / cyan / emerald / amber / rose /
    /// indigo / slate / mono). The renderer resolves to RGB.
    public let theme: String?
    /// Auto-dismiss after N seconds. Banners default to 8s; sheet/modal
    /// stay until dismissed by the user. 0 / nil = never auto-dismiss.
    public let ttlSeconds: Int

    /// Parse a single inbox JSON object. Returns nil on missing/bad fields
    /// rather than throwing — one bad message shouldn't kill the queue.
    static func parse(_ obj: [String: Any]) -> DijjiMessage? {
        guard let id   = obj["id"] as? String,
              let kRaw = obj["kind"] as? String,
              let kind = Kind(rawValue: kRaw)
        else { return nil }
        let cfg = (obj["config"] as? [String: Any]) ?? [:]
        return DijjiMessage(
            id: id,
            kind: kind,
            title:   cfg["title"]    as? String,
            body:    cfg["body"]     as? String,
            ctaText: cfg["cta_text"] as? String,
            ctaUrl:  cfg["cta_url"]  as? String,
            position: cfg["position"] as? String ?? "top",
            theme:    cfg["theme"]    as? String,
            ttlSeconds: (cfg["ttl_seconds"] as? Int) ?? (kind == .banner ? 8 : 0)
        )
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
