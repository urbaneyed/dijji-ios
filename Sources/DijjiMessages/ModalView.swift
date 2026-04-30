#if canImport(UIKit)
import UIKit
import DijjiCore

/// Centered modal — a card in the middle of the screen with a dim
/// backdrop. Used when the message is more important than a banner but
/// less commitment than a full bottom sheet (e.g. confirmation prompts,
/// quick announcements).
///
/// Tap backdrop to dismiss; tap close (×) to dismiss; tap CTA to fire
/// click + open URL + dismiss.
enum ModalPresenter {
    static func present(
        message: DijjiMessage,
        on host: UIViewController,
        onDismiss: @escaping (MessageHost.DismissReason) -> Void
    ) {
        let vc = ModalViewController(message: message, onDismiss: onDismiss)
        vc.modalPresentationStyle = .overFullScreen
        vc.modalTransitionStyle = .crossDissolve
        host.present(vc, animated: true)
    }
}

private final class ModalViewController: UIViewController {

    private let message: DijjiMessage
    private let onDismiss: (MessageHost.DismissReason) -> Void
    private let card = UIView()
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

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 18
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.22
        card.layer.shadowRadius = 28
        card.layer.shadowOffset = CGSize(width: 0, height: 12)
        card.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        card.alpha = 0
        view.addSubview(card)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = .tertiaryLabel
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(backdropTapped), for: .touchUpInside)
        card.addSubview(close)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        if let imgUrl = message.imageUrl, !imgUrl.isEmpty {
            let imgView = UIImageView()
            imgView.contentMode = .scaleAspectFill
            imgView.clipsToBounds = true
            imgView.layer.cornerRadius = 12
            imgView.backgroundColor = UIColor(white: 0.1, alpha: 1)
            imgView.heightAnchor.constraint(equalTo: imgView.widthAnchor, multiplier: 9.0/16.0).isActive = true
            DijjiImageLoader.load(imgUrl, into: imgView)
            stack.addArrangedSubview(imgView)
        }

        if let t = message.title, !t.isEmpty {
            let lbl = UILabel()
            lbl.text = t
            lbl.font = .systemFont(ofSize: 20, weight: .semibold)
            lbl.textColor = .label
            lbl.numberOfLines = 0
            stack.addArrangedSubview(lbl)
        }
        if let b = message.body, !b.isEmpty {
            let lbl = UILabel()
            lbl.text = b
            lbl.font = .systemFont(ofSize: 15)
            lbl.textColor = .secondaryLabel
            lbl.numberOfLines = 0
            stack.addArrangedSubview(lbl)
        }
        if let c = message.ctaText, !c.isEmpty {
            let rgb = DijjiTheme.color(for: message.theme)
            let btn = UIButton(type: .system)
            btn.setTitle(c, for: .normal)
            btn.setTitleColor(.white, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            btn.backgroundColor = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            btn.layer.cornerRadius = 10
            btn.contentEdgeInsets = UIEdgeInsets(top: 12, left: 22, bottom: 12, right: 22)
            btn.heightAnchor.constraint(equalToConstant: 46).isActive = true
            btn.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 440),

            close.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            close.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            close.widthAnchor.constraint(equalToConstant: 30),
            close.heightAnchor.constraint(equalToConstant: 30),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -28),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4) {
            self.card.transform = .identity
            self.card.alpha = 1
            self.view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
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

    private func dismiss(reason: MessageHost.DismissReason) {
        guard !dismissed else { return }
        dismissed = true
        UIView.animate(withDuration: 0.24, animations: {
            self.card.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            self.card.alpha = 0
            self.view.backgroundColor = UIColor.black.withAlphaComponent(0)
        }, completion: { _ in
            self.dismiss(animated: false) {
                self.onDismiss(reason)
            }
        })
    }
}
#endif
