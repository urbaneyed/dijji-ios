import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Wraps UIApplication lifecycle notifications so DijjiClient can react
/// to foreground/background transitions without touching the host app's
/// AppDelegate. Detached on opt-out so we stop firing pings.
final class Lifecycle {
    var onForeground: (() -> Void)?
    var onBackground: (() -> Void)?
    private var attached = false

    func attach() {
        guard !attached else { return }
        attached = true
        #if canImport(UIKit)
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(didEnterFg), name: UIApplication.willEnterForegroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(didEnterBg), name: UIApplication.didEnterBackgroundNotification, object: nil)
        // didFinishLaunching is too late for the very first launch — Dijji
        // is initialized from there, so the app is already foreground. Only
        // willEnterForeground fires on subsequent foreground transitions.
        #endif
    }

    func detach() {
        guard attached else { return }
        attached = false
        NotificationCenter.default.removeObserver(self)
    }

    deinit { detach() }

    @objc private func didEnterFg() { onForeground?() }
    @objc private func didEnterBg() { onBackground?() }
}
