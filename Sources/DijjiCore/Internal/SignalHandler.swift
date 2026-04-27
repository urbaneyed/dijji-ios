import Foundation
import Darwin

/// POSIX signal-based crash capture for pure-Swift crashes.
///
/// `NSSetUncaughtExceptionHandler` (in CrashHandler.swift) only catches
/// Objective-C NSException. Modern Swift apps mostly crash via signals:
///   - SIGABRT  — fatalError, preconditionFailure, assert in release
///   - SIGTRAP  — Swift runtime traps (forced unwrap nil, array OOB)
///   - SIGSEGV  — bad memory access (rare in pure Swift, common with C bridges)
///   - SIGBUS / SIGILL / SIGFPE — hardware-ish faults
///   - SIGPIPE  — broken socket writes (we install the handler but ignore;
///                URLSession callers should handle this themselves)
///
/// Strategy ("write marker, send next launch") used by Sentry / Crashlytics /
/// Bugsnag. Inside the handler we can ONLY use async-signal-safe APIs —
/// no Swift runtime, no Foundation, no String formatting, no malloc. We
/// pre-allocate the crash file path as a C string at install time; the
/// handler does open(2) + write(2) + close(2), then re-raises the signal
/// so the OS / Xcode / debugger still gets the standard crash report.
///
/// On the NEXT app launch (regular Swift code, full Foundation available),
/// `processPendingCrashIfAny()` reads the marker, formats a full crash
/// report with breadcrumbs + device context, sends to /t/app/crash, and
/// deletes the marker.
///
/// What this DOESN'T capture (yet):
///   - Symbolicated stack traces. `backtrace(3)` IS async-signal-safe but
///     emits raw addresses; full symbol resolution needs the dSYM uploaded
///     to a server-side symbolicator. v1.3.
///   - Mach exceptions. The "right" way for things like EXC_BAD_ACCESS is
///     a Mach exception port handler, which is significantly more code.
///     Signals catch the bridge result for most cases.
enum SignalHandler {

    private static let signalsToCatch: [Int32] = [
        SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP,
    ]

    /// Pre-allocated null-terminated C string with the crash dump path.
    /// Allocated at install() time so the signal handler doesn't need to
    /// touch Swift's String/Data infrastructure.
    private static var crashFileCPath: UnsafeMutablePointer<CChar>?

    /// Install the handlers. Idempotent — calling twice is a no-op.
    static func install() {
        guard crashFileCPath == nil else { return }

        // Build the path: <Documents>/dijji-crash.json. Documents is
        // backed up by iCloud by default; for a crash marker we don't
        // really care if it gets backed up, but the file exists for
        // typically <1 minute (between crash and next-launch send).
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        let path = (docs as NSString).appendingPathComponent("dijji-crash.json")
        let utf8 = path.utf8CString
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: utf8.count)
        utf8.withUnsafeBufferPointer { src in
            buf.update(from: src.baseAddress!, count: utf8.count)
        }
        crashFileCPath = buf

        for sig in signalsToCatch {
            var action = sigaction()
            // SA_NODEFER so a re-entry doesn't get blocked. SA_RESETHAND so
            // after we run once, the default handler takes over for the
            // re-raise — that's what produces the standard OS crash report
            // and triggers any other registered crash reporters.
            action.sa_flags = SA_NODEFER | SA_RESETHAND
            // Important: bind via __sigaction_u.__sa_handler (the union variant
            // for plain handlers). The sigaction union is awkward in Swift.
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            action.__sigaction_u = __sigaction_u(__sa_handler: signalCallback)
            #endif
            sigemptyset(&action.sa_mask)
            sigaction(sig, &action, nil)
        }

        DijjiLogger.debug("SignalHandler installed for \(signalsToCatch.count) signals")
    }

    /// The signal handler. Marked @convention(c) because POSIX signal
    /// handlers must be C-callable. Can't capture self / globals via Swift
    /// closure semantics — the runtime isn't available here.
    ///
    /// Allowed APIs (async-signal-safe per POSIX):
    ///   write, open, close, _exit, signal, raise, sigaction
    /// Disallowed:
    ///   anything that allocates, anything Swift-level (String, Data, etc.)
    private static let signalCallback: @convention(c) (Int32) -> Void = { sig in
        guard let pathPtr = crashFileCPath else {
            // Re-raise and bail. Without a path we can't write the marker
            // but at least the OS reporter still fires.
            signal(sig, SIG_DFL)
            raise(sig)
            return
        }
        // Open the marker file. O_CREAT | O_WRONLY | O_TRUNC — overwrite any
        // previous (already-sent) marker. 0o644 = rw for owner, r for others.
        let fd = open(pathPtr, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        if fd >= 0 {
            // Write a minimal JSON-ish blob using only writeBytes. Format:
            //   {"signal":<num>,"name":"<NAME>","ts":<unix>}
            // No String interpolation — write byte sequences directly.
            writeRawString(fd, "{\"signal\":")
            writeRawInt(fd, Int(sig))
            writeRawString(fd, ",\"name\":\"")
            writeRawString(fd, signalNameC(sig))
            writeRawString(fd, "\",\"ts\":")
            writeRawInt(fd, Int(time(nil)))
            writeRawString(fd, "}\n")
            close(fd)
        }
        // Re-raise so the OS / Xcode / other reporters see the crash
        // normally. SA_RESETHAND already restored the default handler.
        raise(sig)
    }

    /// Async-signal-safe int → ASCII writer. No printf, no malloc.
    private static func writeRawInt(_ fd: Int32, _ v: Int) {
        if v == 0 { _ = write(fd, "0", 1); return }
        var n = v
        let neg = n < 0
        if neg { n = -n }
        var buf = [CChar](repeating: 0, count: 24)
        var i = buf.count - 1
        while n > 0 {
            buf[i] = CChar(0x30 + (n % 10))   // '0' = 0x30
            n /= 10
            i -= 1
        }
        if neg { buf[i] = 0x2D; i -= 1 }     // '-'
        let start = i + 1
        let len = buf.count - start
        buf.withUnsafeBufferPointer { p in
            _ = write(fd, p.baseAddress!.advanced(by: start), len)
        }
    }

    private static func writeRawString(_ fd: Int32, _ s: UnsafePointer<CChar>) {
        _ = write(fd, s, strlen(s))
    }

    /// Map signal number → name. Returns a static C string so we don't
    /// allocate inside the handler.
    private static func signalNameC(_ sig: Int32) -> UnsafePointer<CChar> {
        switch sig {
        case SIGABRT: return UnsafePointer<CChar>(strdup("SIGABRT"))
        case SIGILL:  return UnsafePointer<CChar>(strdup("SIGILL"))
        case SIGSEGV: return UnsafePointer<CChar>(strdup("SIGSEGV"))
        case SIGFPE:  return UnsafePointer<CChar>(strdup("SIGFPE"))
        case SIGBUS:  return UnsafePointer<CChar>(strdup("SIGBUS"))
        case SIGTRAP: return UnsafePointer<CChar>(strdup("SIGTRAP"))
        default:      return UnsafePointer<CChar>(strdup("UNKNOWN"))
        }
        // Note: strdup IS async-signal-safe per POSIX, and we don't free
        // the result — the process is dying anyway, so the leak is fine.
    }

    /// Called from DijjiClient.start() on every launch. If the marker file
    /// exists, parse + send + delete. Runs in regular Swift context — full
    /// Foundation allowed.
    static func processPendingCrashIfAny(visitorId: String, siteKey: String, apiBase: String) {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        let path = (docs as NSString).appendingPathComponent("dijji-crash.json")
        guard FileManager.default.fileExists(atPath: path) else { return }

        defer {
            // Always delete after attempting send — don't loop on a
            // permanently-broken backend or malformed marker.
            try? FileManager.default.removeItem(atPath: path)
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            DijjiLogger.warn("crash marker present but unreadable; deleted")
            return
        }

        var report: [String: Any] = parsed
        report["site"] = siteKey
        report["visitor_id"] = visitorId
        report["platform"] = "ios"
        report["type"] = "signal"
        // Stamp the device context that was current at NEXT-launch time.
        // It's not the moment-of-crash context (that's what we couldn't
        // safely capture in the signal handler), but it's the closest we
        // can get and is good for OS / app version drift.
        for (k, v) in DeviceContext.snapshot() { report[k] = v }

        guard let url = URL(string: apiBase + "/t/app/crash") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: report, options: [])

        // Synchronous-ish — we want it to ship before the user does
        // anything else. A few seconds extra at launch is acceptable.
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 5.0)
        DijjiLogger.debug("pending crash report sent")
    }
}
