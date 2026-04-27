#if canImport(UIKit)
import UIKit
import DijjiCore

/// Top or bottom banner — full-width strip, slides in, optionally
/// auto-dismisses after the message's TTL.
///
/// Visual: themed accent background, white text, optional CTA pill at
/// the trailing edge, close button. Tapping anywhere on the banner
/// (when `cta_url` is set) counts as a CTA tap.
final class BannerView: UIView {

    private let message: DijjiMessage
    private let onDismiss: (MessageHost.DismissReason) -> Void
    private var topConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    private var dismissTimer: Timer?

    init(message: DijjiMessage, onDismiss: @escaping (MessageHost.DismissReason) -> Void) {
        self.message = message
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func attach(to host: UIView) {
        host.addSubview(self)
        translatesAutoresizingMaskIntoConstraints = false
        let bottomPosition = (message.position == "bottom")
        // Slide in from the appropriate edge. Initial position is fully
        // off-screen; we animate to 0 in the next runloop tick.
        if bottomPosition {
            bottomConstraint = bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: 80)
            bottomConstraint?.isActive = true
        } else {
            topConstraint = topAnchor.constraint(equalTo: host.topAnchor, constant: -80)
            topConstraint?.isActive = true
        }
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        host.layoutIfNeeded()
        UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4) {
            self.topConstraint?.constant = 0
            self.bottomConstraint?.constant = 0
            host.layoutIfNeeded()
        }

        if message.ttlSeconds > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(message.ttlSeconds), repeats: false) { [weak self] _ in
                self?.dismiss(reason: .autoExpired)
            }
        }
    }

    private func buildUI() {
        let rgb = DijjiTheme.color(for: message.theme)
        backgroundColor = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)

        // Vertical stack — title above body. If only one is set the layout
        // collapses to a single line cleanly.
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let t = message.title, !t.isEmpty {
            let lbl = UILabel()
            lbl.text = t
            lbl.font = .systemFont(ofSize: 14, weight: .semibold)
            lbl.textColor = .white
            lbl.numberOfLines = 1
            lbl.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(lbl)
        }
        if let b = message.body, !b.isEmpty {
            let lbl = UILabel()
            lbl.text = b
            lbl.font = .systemFont(ofSize: 12.5, weight: .regular)
            lbl.textColor = UIColor(white: 1, alpha: 0.88)
            lbl.numberOfLines = 1
            lbl.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(lbl)
        }
        addSubview(stack)

        // CTA pill at the trailing edge (if cta_text + cta_url set). Tap
        // it to fire the click event + open the URL. The whole banner is
        // also tappable when cta_url is set — gesture handler below.
        let ctaPill = UIView()
        ctaPill.translatesAutoresizingMaskIntoConstraints = false
        if let c = message.ctaText, !c.isEmpty, message.ctaUrl != nil {
            ctaPill.backgroundColor = UIColor(white: 1, alpha: 0.18)
            ctaPill.layer.cornerRadius = 7
            let lbl = UILabel()
            lbl.text = c
            lbl.font = .systemFont(ofSize: 12.5, weight: .semibold)
            lbl.textColor = .white
            lbl.translatesAutoresizingMaskIntoConstraints = false
            ctaPill.addSubview(lbl)
            NSLayoutConstraint.activate([
                lbl.leadingAnchor.constraint(equalTo: ctaPill.leadingAnchor, constant: 12),
                lbl.trailingAnchor.constraint(equalTo: ctaPill.trailingAnchor, constant: -12),
                lbl.topAnchor.constraint(equalTo: ctaPill.topAnchor, constant: 6),
                lbl.bottomAnchor.constraint(equalTo: ctaPill.bottomAnchor, constant: -6),
            ])
            addSubview(ctaPill)
        }

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeBtn.tintColor = UIColor(white: 1, alpha: 0.75)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(closeBtn)

        // Layout — banner is ~62pt tall (44 content + 18 padding) on top
        // mode; bottom mode adds the home-indicator inset via safe area
        // anchors below.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 18),
            stack.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: ctaPill.leadingAnchor, constant: -10),

            ctaPill.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            ctaPill.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -10),

            closeBtn.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            closeBtn.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 26),
            closeBtn.heightAnchor.constraint(equalToConstant: 26),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            safeAreaLayoutGuide.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        // Whole-banner tap → CTA. Ignored when no cta_url. Close button
        // intercepts the tap before it reaches us.
        if message.ctaUrl != nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(ctaTapped))
            addGestureRecognizer(tap)
            // Cursor / a11y hint that this is a tap target
            isAccessibilityElement = true
            accessibilityTraits = .button
        }
    }

    @objc private func closeTapped() {
        dismiss(reason: .userClosed)
    }

    @objc private func ctaTapped() {
        guard let raw = message.ctaUrl, let url = URL(string: raw) else {
            dismiss(reason: .userClosed); return
        }
        Dijji.track("__dijji_message_clicked", properties: [
            "message_id": message.id,
            "kind": message.kind.rawValue,
            "cta_url": raw,
        ])
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        dismiss(reason: .ctaTapped)
    }

    private func dismiss(reason: MessageHost.DismissReason) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        UIView.animate(withDuration: 0.28, animations: {
            // Slide back out — invert the entry direction
            self.topConstraint?.constant = -80
            self.bottomConstraint?.constant = 80
            self.superview?.layoutIfNeeded()
        }, completion: { _ in
            self.removeFromSuperview()
            self.onDismiss(reason)
        })
    }
}
#endif
