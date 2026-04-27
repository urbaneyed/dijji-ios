#if canImport(UIKit)
import UIKit
import DijjiCore

/// Bottom-sheet presenter. Slides up from the bottom of the screen with a
/// rounded top, dim backdrop. Tap backdrop or drag down past the threshold
/// to dismiss; tap CTA to fire click event + open URL.
///
/// Implemented as a UIViewController that gets `present`-ed via the host
/// view controller so the standard iOS modal lifecycle handles
/// orientation, status bar, safe-area, etc. for free.
enum BottomSheetPresenter {

    static func present(
        message: DijjiMessage,
        on host: UIViewController,
        onDismiss: @escaping (MessageHost.DismissReason) -> Void
    ) {
        let vc = BottomSheetViewController(message: message, onDismiss: onDismiss)
        vc.modalPresentationStyle = .overFullScreen
        vc.modalTransitionStyle = .crossDissolve
        host.present(vc, animated: true)
    }
}

private final class BottomSheetViewController: UIViewController {

    private let message: DijjiMessage
    private let onDismiss: (MessageHost.DismissReason) -> Void
    private let card = UIView()
    private var cardBottomConstraint: NSLayoutConstraint?
    private var dismissed = false

    init(message: DijjiMessage, onDismiss: @escaping (MessageHost.DismissReason) -> Void) {
        self.message = message
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0)

        // Backdrop tap-to-dismiss
        let bg = UIControl()
        bg.translatesAutoresizingMaskIntoConstraints = false
        bg.addTarget(self, action: #selector(backdropTapped), for: .touchUpInside)
        view.addSubview(bg)
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bg.topAnchor.constraint(equalTo: view.topAnchor),
            bg.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Card itself — light surface, large rounded top corners
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.systemBackground
        card.layer.cornerRadius = 22
        card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.18
        card.layer.shadowRadius = 24
        card.layer.shadowOffset = CGSize(width: 0, height: -4)
        view.addSubview(card)

        // Drag handle — visual cue that the sheet is dismissable by
        // dragging. The actual gesture is on the card itself below.
        let handle = UIView()
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.backgroundColor = UIColor.tertiaryLabel
        handle.layer.cornerRadius = 2.5
        card.addSubview(handle)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        if let t = message.title, !t.isEmpty {
            let lbl = UILabel()
            lbl.text = t
            lbl.font = .systemFont(ofSize: 22, weight: .semibold)
            lbl.textColor = .label
            lbl.numberOfLines = 0
            stack.addArrangedSubview(lbl)
        }
        if let b = message.body, !b.isEmpty {
            let lbl = UILabel()
            lbl.text = b
            lbl.font = .systemFont(ofSize: 15.5)
            lbl.textColor = .secondaryLabel
            lbl.numberOfLines = 0
            stack.addArrangedSubview(lbl)
        }
        if let c = message.ctaText, !c.isEmpty {
            // Theme-tinted primary CTA button. Full-width, prominent.
            let rgb = DijjiTheme.color(for: message.theme)
            let btn = UIButton(type: .system)
            btn.setTitle(c, for: .normal)
            btn.setTitleColor(.white, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 15.5, weight: .semibold)
            btn.backgroundColor = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            btn.layer.cornerRadius = 10
            btn.contentEdgeInsets = UIEdgeInsets(top: 14, left: 22, bottom: 14, right: 22)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 50).isActive = true
            btn.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }

        cardBottomConstraint = card.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 600)
        cardBottomConstraint?.isActive = true
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            handle.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            handle.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 40),
            handle.heightAnchor.constraint(equalToConstant: 5),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: card.safeAreaLayoutGuide.bottomAnchor, constant: -22),
        ])

        // Drag-to-dismiss
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        card.addGestureRecognizer(pan)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.35) {
            self.cardBottomConstraint?.constant = 0
            self.view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            self.view.layoutIfNeeded()
        }
    }

    @objc private func backdropTapped() { dismiss(reason: .userClosed) }

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

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let translation = g.translation(in: view).y
        switch g.state {
        case .changed:
            // Resist upward drag (negative); follow downward drag 1:1
            cardBottomConstraint?.constant = max(0, translation)
        case .ended, .cancelled:
            // Past 80pt OR fast downward swipe → dismiss
            let velocity = g.velocity(in: view).y
            if translation > 80 || velocity > 600 {
                dismiss(reason: .userClosed)
            } else {
                UIView.animate(withDuration: 0.24) {
                    self.cardBottomConstraint?.constant = 0
                    self.view.layoutIfNeeded()
                }
            }
        default: break
        }
    }

    private func dismiss(reason: MessageHost.DismissReason) {
        guard !dismissed else { return }
        dismissed = true
        UIView.animate(withDuration: 0.28, animations: {
            self.cardBottomConstraint?.constant = 600
            self.view.backgroundColor = UIColor.black.withAlphaComponent(0)
            self.view.layoutIfNeeded()
        }, completion: { _ in
            self.dismiss(animated: false) {
                self.onDismiss(reason)
            }
        })
    }
}
#endif
