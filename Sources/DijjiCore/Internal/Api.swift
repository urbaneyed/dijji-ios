import Foundation

/// Thin URLSession wrapper for Dijji ingestion. No external deps. All POSTs
/// fire-and-forget by default — analytics calls don't block your app.
/// Retry is at the queue layer (event flushes), not here.
final class Api {
    private let baseURL: String
    private let siteKey: String
    private let session: URLSession

    init(baseURL: String, siteKey: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.siteKey = siteKey
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    /// POST a JSON body. Calls `onComplete` with success/failure on the
    /// session's delegate queue. Don't rely on completion order — multiple
    /// in-flight requests may complete out of order.
    func post(path: String, body: [String: Any], onComplete: @escaping (Bool) -> Void) {
        guard let url = URL(string: baseURL + path) else { onComplete(false); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
        } catch {
            DijjiLogger.warn("json encode failed: \(error)")
            onComplete(false); return
        }
        let task = session.dataTask(with: req) { _, resp, err in
            if let err = err {
                DijjiLogger.debug("POST \(path) failed: \(err.localizedDescription)")
                onComplete(false); return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            DijjiLogger.debug("POST \(path) -> \(code)")
            // Anything 2xx counts as success — most ingestion endpoints
            // 204 No Content. 4xx/5xx are failures and the caller (queue)
            // will retry.
            onComplete((200..<300).contains(code))
        }
        task.resume()
    }
}
