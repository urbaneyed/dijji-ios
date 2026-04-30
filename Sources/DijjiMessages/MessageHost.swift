import Foundation
#if canImport(UIKit)
import UIKit
#endif
import DijjiCore

/// Coordinates in-app message presentation. One message visible at a time;
/// new messages while one's on-screen go into a queue and present in
/// arrival order. Renderers (BannerView / BottomSheetView / ModalView) all
/// notify back via `messageDismissed(id:reason:)` so we know when to fire
/// the next one off the queue.
///
/// Thread safety: `show()` and `dismiss()` are main-thread-only — UIKit
/// requirement. DijjiMessages.startPolling already dispatches to main
/// before calling show(), so callers don't need to.
final class MessageHost {

    static let shared = MessageHost()
    private init() {}

    private var queue: [DijjiMessage] = []
    private var current: DijjiMessage?
    // Held weakly so the view's lifetime is governed by its host. UIView
    // import is conditional on UIKit availability — non-UIKit targets
    // (macOS swift build for tests) skip the field entirely.
    #if canImport(UIKit)
    private weak var currentView: UIView?
    #endif

    /// Reasons we fire as the `outcome` field on the dismiss event. Lets
    /// the dashboard distinguish "user tapped CTA" from "auto-expired".
    enum DismissReason: String {
        case userClosed = "user_closed"
        case ctaTapped  = "cta_tapped"
        case autoExpired = "auto_expired"
    }

    /// Public entry — DijjiMessages.startPolling calls this for every
    /// inbox message returned. If something's already showing, the new
    /// message queues; if not, it presents immediately.
    func show(_ message: DijjiMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.current != nil {
                self.queue.append(message)
                return
            }
            self.present(message)
        }
    }

    /// Inbox endpoint returned us a message — fire the received event so
    /// the dashboard's delivery rate is accurate even if the user dismisses
    /// before tapping the CTA.
    private func fireReceived(_ message: DijjiMessage) {
        Dijji.track("__dijji_message_received", properties: [
            "message_id": message.id,
            "kind": message.kind.rawValue,
        ])
    }

    private func present(_ message: DijjiMessage) {
        #if canImport(UIKit)
        guard let host = topViewController() else {
            // No host yet — usually means we polled before any UI is up.
            // Re-queue to retry on the next tick rather than dropping.
            queue.append(message)
            return
        }
        current = message
        fireReceived(message)
        switch message.kind {
        case .banner:
            let v = BannerView(message: message, onDismiss: { [weak self] reason in
                self?.didDismiss(message, reason: reason)
            })
            v.attach(to: host.view)
            currentView = v
        case .bottomSheet:
            BottomSheetPresenter.present(
                message: message, on: host,
                onDismiss: { [weak self] reason in self?.didDismiss(message, reason: reason) }
            )
        case .modal:
            ModalPresenter.present(
                message: message, on: host,
                onDismiss: { [weak self] reason in self?.didDismiss(message, reason: reason) }
            )
        case .hero:
            HeroPresenter.present(
                message: message, on: host,
                onDismiss: { [weak self] reason in self?.didDismiss(message, reason: reason) }
            )
        case .nps:
            NpsPresenter.present(
                message: message, on: host,
                onDismiss: { [weak self] reason in self?.didDismiss(message, reason: reason) }
            )
        case .reactions:
            ReactionsPresenter.present(
                message: message, on: host,
                onDismiss: { [weak self] reason in self?.didDismiss(message, reason: reason) }
            )
        case .countdown:
            CountdownPresenter.present(
                message: message, on: host,
                onDismiss: { [weak self] reason in self?.didDismiss(message, reason: reason) }
            )
        }
        #endif
    }

    private func didDismiss(_ message: DijjiMessage, reason: DismissReason) {
        Dijji.track("__dijji_message_dismissed", properties: [
            "message_id": message.id,
            "kind": message.kind.rawValue,
            "outcome": reason.rawValue,
        ])
        current = nil
        #if canImport(UIKit)
        currentView = nil
        #endif
        // Drain the next queued message, if any. Brief delay so dismiss
        // animations finish before the next one slides in — avoids the
        // visual stutter of two messages overlapping during transition.
        if !queue.isEmpty {
            let next = queue.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.present(next)
            }
        }
    }

    #if canImport(UIKit)
    /// Walk the responder chain to find the topmost presented controller.
    /// Used so messages overlay any modal sheets, alerts, etc. that the
    /// host app has already presented.
    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let active = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        guard var top = active?.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
    #endif
}
