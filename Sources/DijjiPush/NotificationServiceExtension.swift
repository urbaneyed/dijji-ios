import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Helper for the host app's Notification Service Extension target.
/// REQUIRED for rich pushes (image attachments) on iOS.
///
/// To enable rich pushes:
///   1. In Xcode: File → New → Target → Notification Service Extension.
///      Name it whatever you like (e.g. "DijjiNotificationService").
///   2. Add `DijjiPush` as a dependency of the new target.
///   3. Replace the generated NotificationService.swift body with:
///
///        import UserNotifications
///        import DijjiPush
///
///        class NotificationService: UNNotificationServiceExtension {
///            override func didReceive(_ request: UNNotificationRequest,
///                                     withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
///                DijjiNotificationServiceHelper.handle(request, contentHandler: contentHandler)
///            }
///        }
///
/// That's it. The helper looks for `image_url` in the push payload (which
/// the Dijji backend sets when you fill the "Image URL" field in the push
/// composer or trigger), downloads the image to a temp location, attaches
/// it to the notification, and hands the rendered content back to iOS.
///
/// Falls back gracefully: if there's no image_url, the notification
/// renders as plain text. If the image download fails for any reason
/// (timeout, 404, non-image MIME), we log + still display the text-only
/// notification rather than dropping the push entirely.
public enum DijjiNotificationServiceHelper {

    #if canImport(UserNotifications)
    public static func handle(
        _ request: UNNotificationRequest,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent ?? UNMutableNotificationContent()

        guard let urlString = request.content.userInfo["image_url"] as? String,
              let imageUrl = URL(string: urlString)
        else {
            // No image — just deliver as-is. This is the default path for
            // every text-only push, so the early return is fast.
            contentHandler(bestAttempt)
            return
        }

        // 25-second cap — APNs gives the extension at most 30s before
        // killing it; leave 5s of headroom for attachment serialization.
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25
        let session = URLSession(configuration: cfg)
        session.downloadTask(with: imageUrl) { tempUrl, response, error in
            defer { contentHandler(bestAttempt) }
            guard error == nil, let tempUrl = tempUrl else { return }
            // Move the file to a path with a real image extension — APNs
            // is picky about attachment file types, and tempUrl has no
            // extension by default.
            let ext = inferExtension(from: response, fallbackUrl: imageUrl)
            let dest = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            do {
                try FileManager.default.moveItem(at: tempUrl, to: dest)
                let attachment = try UNNotificationAttachment(
                    identifier: "dijji-image",
                    url: dest,
                    options: nil
                )
                bestAttempt.attachments = [attachment]
            } catch {
                // Attachment failed — keep the text-only content. Don't
                // crash the extension; better to deliver a plain push
                // than no push at all.
            }
        }.resume()
    }

    /// Guess the file extension from Content-Type or URL path. APNs
    /// attachment validation matches by extension, not by sniffing the
    /// content, so getting this right matters.
    private static func inferExtension(from response: URLResponse?, fallbackUrl: URL) -> String {
        if let mime = (response as? HTTPURLResponse)?.allHeaderFields["Content-Type"] as? String {
            let lower = mime.lowercased()
            if lower.contains("image/jpeg") || lower.contains("image/jpg") { return "jpg" }
            if lower.contains("image/png")  { return "png" }
            if lower.contains("image/gif")  { return "gif" }
            if lower.contains("video/mp4")  { return "mp4" }
        }
        let pathExt = fallbackUrl.pathExtension.lowercased()
        if !pathExt.isEmpty {
            return pathExt
        }
        return "jpg"
    }
    #endif
}
