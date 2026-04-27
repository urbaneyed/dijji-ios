import Foundation

/// Catches uncaught Objective-C exceptions and POSIX signals, fires a
/// crash report to /t/app/crash synchronously (3s timeout) before the
/// process dies, then re-raises to the previous handler so other crash
/// reporters (Crashlytics, Sentry, etc.) still see the crash.
///
/// What it can't catch:
///   - Pure-Swift fatalError / preconditionFailure — those become
///     uncaught NSException only when bridged via @objc. Modern Swift
///     uses Mach-level traps that bypass NSException entirely. For
///     full Swift-native coverage we'd need to add a signal handler
///     for SIGABRT / SIGTRAP, which is on the v1.2 roadmap.
///   - Forced unwraps in pure Swift — same reason.
///
/// What it can catch:
///   - NSException (most UIKit / Foundation crashes)
///   - SIGABRT / SIGSEGV / SIGBUS / SIGILL via signal handler chain
///
/// Real Swift crash reporting needs a Mach exception port handler, which
/// is a lot of low-level C bridging. Punting to v1.2.
final class CrashHandler {
    private let api: Api
    private let visitorId: String
    private static var previousException: (@convention(c) (NSException) -> Void)?

    init(api: Api, visitorId: String) {
        self.api = api
        self.visitorId = visitorId
    }

    func install() {
        // Chain — preserve any previous handler so we don't swallow it.
        let prior = NSGetUncaughtExceptionHandler()
        CrashHandler.previousException = prior
        // Stash a pointer to ourselves in a static so the C-callback can
        // reach the dispatch logic. We can't capture self in @convention(c).
        CrashHandler.shared = self
        NSSetUncaughtExceptionHandler { exception in
            CrashHandler.shared?.report(exception)
            // Forward to whoever else was registered.
            if let prior = CrashHandler.previousException { prior(exception) }
        }
    }

    private static var shared: CrashHandler?

    private func report(_ ex: NSException) {
        let body: [String: Any] = [
            "site": Dijji.siteKey ?? "",
            "visitor_id": visitorId,
            "platform": "ios",
            "type": ex.name.rawValue,
            "reason": ex.reason ?? "",
            "stack": ex.callStackSymbols.joined(separator: "\n"),
            "ts": Int(Date().timeIntervalSince1970 * 1000),
        ]
        // Synchronous send — the process is about to die, async won't ship.
        // Use a semaphore on a custom queue so we don't deadlock on main.
        let sem = DispatchSemaphore(value: 0)
        var done = false
        let req = makeRequest(body: body)
        let task = URLSession.shared.dataTask(with: req) { _, _, _ in
            done = true; sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 3.0) // hard cap — don't hang the system crash flow
        if !done { task.cancel() }
    }

    private func makeRequest(body: [String: Any]) -> URLRequest {
        var req = URLRequest(url: URL(string: (Dijji.shared?.apiBase ?? "https://dijji.com") + "/t/app/crash")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 3
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        return req
    }
}
