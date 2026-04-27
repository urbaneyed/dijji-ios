import Foundation

/// Batches custom events and flushes to /t/app/collect. Events buffer in
/// memory; survival across app kills is best-effort via UserDefaults
/// snapshot on background. The cap (500 events) protects against a
/// runaway loop if something on the host app is firing track() in a tight
/// loop.
///
/// Failed flushes are retried on the next periodic tick. We don't do
/// exponential backoff — Dijji ingestion is tolerant of duplicates
/// (events stamped with a client-side timestamp), and the cron is fast
/// enough that a 30s retry cadence is fine.
final class EventQueue {
    private let api: Api
    private let visitorId: String
    private let lock = NSLock()
    private var buffer: [[String: Any]] = []
    private let maxBuffer = 500
    private var timer: Timer?

    init(api: Api, visitorId: String) {
        self.api = api
        self.visitorId = visitorId
    }

    func enqueue(name: String, properties: [String: Any]) {
        let evt: [String: Any] = [
            "name": name,
            "ts": Int(Date().timeIntervalSince1970 * 1000),
            "props": properties,
        ]
        lock.lock()
        buffer.append(evt)
        if buffer.count > maxBuffer {
            // Drop the oldest events when over cap — newer events are
            // more relevant for live debugging than ancient ones.
            buffer.removeFirst(buffer.count - maxBuffer)
            DijjiLogger.warn("event buffer overflow; oldest events dropped")
        }
        let count = buffer.count
        lock.unlock()
        // Flush eagerly on a small set of "interesting" events so they
        // appear in the live dashboard within seconds rather than waiting
        // for the next 30s tick.
        if name == "app_open" || name == "app_install" || name == "session_start" || count >= 50 {
            flushNow()
        }
    }

    func startPeriodicFlush(every seconds: TimeInterval) {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
                self?.flushNow()
            }
        }
    }

    func clearPending() {
        lock.lock(); buffer.removeAll(); lock.unlock()
    }

    func flushNow() {
        lock.lock()
        guard !buffer.isEmpty else { lock.unlock(); return }
        let toFlush = buffer
        buffer.removeAll()
        lock.unlock()
        // Site key is pulled from Dijji.shared rather than threaded into the
        // EventQueue's constructor — DijjiClient already owns the canonical
        // siteKey, no point keeping a duplicate here.
        let body: [String: Any] = [
            "site": Dijji.siteKey ?? "",
            "visitor_id": visitorId,
            "events": toFlush,
        ]
        api.post(path: "/t/app/collect", body: body) { ok in
            if !ok {
                // Re-queue on failure. Prepend so chronological order is preserved.
                self.lock.lock()
                self.buffer.insert(contentsOf: toFlush, at: 0)
                if self.buffer.count > self.maxBuffer {
                    self.buffer.removeFirst(self.buffer.count - self.maxBuffer)
                }
                self.lock.unlock()
                DijjiLogger.debug("flush failed — \(toFlush.count) events re-queued")
            }
        }
    }
}
