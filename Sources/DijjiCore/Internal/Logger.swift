import Foundation

/// Internal logger — gated by `Dijji.initialize(debug: true)`. Production
/// apps stay silent; debug builds get [DIJJI] tags in stdout. Logs go
/// through `print()` rather than os.Logger to keep deployment targets
/// flexible (os.Logger requires iOS 14).
enum DijjiLogger {
    static var debugEnabled = false

    static func debug(_ message: @autoclosure () -> String) {
        if debugEnabled { print("[DIJJI] \(message())") }
    }
    static func warn(_ message: @autoclosure () -> String) {
        // Warnings always print — they signal real misconfiguration.
        print("[DIJJI WARN] \(message())")
    }
}
