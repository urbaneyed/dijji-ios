#if canImport(UIKit)
import UIKit
import DijjiCore

// MARK: - Hero — full-bleed takeover with image + dual CTA

enum HeroPresenter {
    static func present(
        message: DijjiMessage,
        on host: UIViewController,
        onDismiss: @escaping (MessageHost.DismissReason) -> Void
    ) {
        let vc = HeroViewController(message: message, onDismiss: onDismiss)
        vc.modalPresentationStyle = .overFullScreen
        vc.modalTransitionStyle = .crossDissolve
        host.present(vc, animated: true)
    }
}

private final class HeroViewController: UIViewController {
    private let message: DijjiMessage
    private let onDismiss: (MessageHost.DismissReason) -> Void
    init(message: DijjiMessage, onDismiss: @escaping (MessageHost.DismissReason) -> Void) {
        self.message = message
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        let rgb = DijjiTheme.color(for: message.theme)
        let accent = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)

        let card = UIView()
        card.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1)
        card.layer.cornerRadius = 24
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        // Hero image area (4:3)
        let imgWrap = UIView()
        imgWrap.translatesAutoresizingMaskIntoConstraints = false
        imgWrap.backgroundColor = accent.withAlphaComponent(0.22)
        card.addSubview(imgWrap)

        let imgView = UIImageView()
        imgView.contentMode = .scaleAspectFill
        imgView.clipsToBounds = true
        imgView.translatesAutoresizingMaskIntoConstraints = false
        imgWrap.addSubview(imgView)
        DijjiImageLoader.load(message.imageUrl, into: imgView)

        // Gradient veil — improves title legibility over photo
        let veil = UIView()
        veil.translatesAutoresizingMaskIntoConstraints = false
        imgWrap.addSubview(veil)
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor.clear.cgColor,
            UIColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 0.85).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        veil.layer.addSublayer(gradient)
        DispatchQueue.main.async { gradient.frame = veil.bounds }

        // Top-right close button
        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeBtn.tintColor = .white
        closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        closeBtn.layer.cornerRadius = 18
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        imgWrap.addSubview(closeBtn)

        // Body text + CTAs
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        if let t = message.title, !t.isEmpty {
            let l = UILabel()
            l.text = t
            l.textColor = UIColor(white: 0.96, alpha: 1)
            l.font = .systemFont(ofSize: 22, weight: .bold)
            l.numberOfLines = 0
            l.textAlignment = .center
            stack.addArrangedSubview(l)
        }
        if let b = message.body, !b.isEmpty {
            let l = UILabel()
            l.text = b
            l.textColor = UIColor(red: 0.71, green: 0.71, blue: 0.78, alpha: 1)
            l.font = .systemFont(ofSize: 14.5)
            l.numberOfLines = 0
            l.textAlignment = .center
            stack.addArrangedSubview(l)
        }

        if let c = message.ctaText, !c.isEmpty {
            let btn = UIButton(type: .system)
            btn.setTitle(c, for: .normal)
            btn.setTitleColor(.white, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            btn.backgroundColor = accent
            btn.layer.cornerRadius = 10
            btn.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)
            stack.addArrangedSubview(btn)
            btn.heightAnchor.constraint(equalToConstant: 52).isActive = true
        }
        if let s = message.secondaryCtaText, !s.isEmpty {
            let btn = UIButton(type: .system)
            btn.setTitle(s, for: .normal)
            btn.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 14)
            btn.backgroundColor = .clear
            btn.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)
            stack.addArrangedSubview(btn)
            btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 420),

            imgWrap.topAnchor.constraint(equalTo: card.topAnchor),
            imgWrap.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            imgWrap.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            imgWrap.heightAnchor.constraint(equalTo: imgWrap.widthAnchor, multiplier: 0.75),

            imgView.topAnchor.constraint(equalTo: imgWrap.topAnchor),
            imgView.bottomAnchor.constraint(equalTo: imgWrap.bottomAnchor),
            imgView.leadingAnchor.constraint(equalTo: imgWrap.leadingAnchor),
            imgView.trailingAnchor.constraint(equalTo: imgWrap.trailingAnchor),

            veil.topAnchor.constraint(equalTo: imgWrap.topAnchor),
            veil.bottomAnchor.constraint(equalTo: imgWrap.bottomAnchor),
            veil.leadingAnchor.constraint(equalTo: imgWrap.leadingAnchor),
            veil.trailingAnchor.constraint(equalTo: imgWrap.trailingAnchor),

            closeBtn.topAnchor.constraint(equalTo: imgWrap.topAnchor, constant: 12),
            closeBtn.trailingAnchor.constraint(equalTo: imgWrap.trailingAnchor, constant: -12),
            closeBtn.widthAnchor.constraint(equalToConstant: 36),
            closeBtn.heightAnchor.constraint(equalToConstant: 36),

            stack.topAnchor.constraint(equalTo: imgWrap.bottomAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true) { self.onDismiss(.userClosed) }
    }
    @objc private func ctaTapped() {
        Dijji.track("__dijji_message_clicked", properties: [
            "message_id": message.id,
            "kind": message.kind.rawValue,
            "cta_url": message.ctaUrl ?? "",
        ])
        if let raw = message.ctaUrl, let url = URL(string: raw) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        dismiss(animated: true) { self.onDismiss(.ctaTapped) }
    }
    @objc private func secondaryTapped() {
        Dijji.track("__dijji_message_clicked", properties: [
            "message_id": message.id,
            "kind": message.kind.rawValue,
            "choice": "secondary",
        ])
        dismiss(animated: true) { self.onDismiss(.userClosed) }
    }
}

// MARK: - NPS — 0–10 colour-graded score sheet

enum NpsPresenter {
    static func present(
        message: DijjiMessage,
        on host: UIViewController,
        onDismiss: @escaping (MessageHost.DismissReason) -> Void
    ) {
        let vc = NpsViewController(message: message, onDismiss: onDismiss)
        vc.modalPresentationStyle = .overFullScreen
        vc.modalTransitionStyle = .coverVertical
        host.present(vc, animated: true)
    }
}

private final class NpsViewController: UIViewController {
    private let message: DijjiMessage
    private let onDismiss: (MessageHost.DismissReason) -> Void
    private var hasSubmitted = false
    private let questionContainer = UIView()
    private let thanksContainer = UIView()

    init(message: DijjiMessage, onDismiss: @escaping (MessageHost.DismissReason) -> Void) {
        self.message = message
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        let rgb = DijjiTheme.color(for: message.theme)
        let accent = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)

        let sheet = UIView()
        sheet.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1)
        sheet.layer.cornerRadius = 20
        sheet.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheet)

        // Drag handle
        let handle = UIView()
        handle.backgroundColor = UIColor(white: 0.3, alpha: 1)
        handle.layer.cornerRadius = 2
        handle.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(handle)

        // Question state container
        questionContainer.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(questionContainer)

        let qLabel = UILabel()
        qLabel.text = message.question ?? "How likely are you to recommend us?"
        qLabel.textColor = UIColor(white: 0.96, alpha: 1)
        qLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        qLabel.numberOfLines = 0
        qLabel.textAlignment = .center
        qLabel.translatesAutoresizingMaskIntoConstraints = false
        questionContainer.addSubview(qLabel)

        let scoreRow = UIStackView()
        scoreRow.axis = .horizontal
        scoreRow.distribution = .fillEqually
        scoreRow.spacing = 4
        scoreRow.translatesAutoresizingMaskIntoConstraints = false
        questionContainer.addSubview(scoreRow)

        for i in 0...10 {
            let color: UIColor
            if i <= 6 { color = UIColor(red: 0.90, green: 0.45, blue: 0.45, alpha: 1) }
            else if i <= 8 { color = UIColor(red: 1.00, green: 0.72, blue: 0.30, alpha: 1) }
            else { color = UIColor(red: 0.40, green: 0.73, blue: 0.42, alpha: 1) }
            let btn = UIButton(type: .system)
            btn.setTitle("\(i)", for: .normal)
            btn.setTitleColor(.white, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
            btn.backgroundColor = color.withAlphaComponent(0.18)
            btn.layer.borderWidth = 1
            btn.layer.borderColor = color.cgColor
            btn.layer.cornerRadius = 8
            btn.tag = i
            btn.addTarget(self, action: #selector(scoreTapped(_:)), for: .touchUpInside)
            btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
            scoreRow.addArrangedSubview(btn)
        }

        let labelsRow = UIStackView()
        labelsRow.axis = .horizontal
        labelsRow.distribution = .fillEqually
        labelsRow.translatesAutoresizingMaskIntoConstraints = false
        questionContainer.addSubview(labelsRow)
        let lowL = UILabel()
        lowL.text = message.lowLabel ?? "Not likely"
        lowL.textColor = UIColor(white: 0.5, alpha: 1)
        lowL.font = .systemFont(ofSize: 11)
        labelsRow.addArrangedSubview(lowL)
        let highL = UILabel()
        highL.text = message.highLabel ?? "Extremely likely"
        highL.textColor = UIColor(white: 0.5, alpha: 1)
        highL.font = .systemFont(ofSize: 11)
        highL.textAlignment = .right
        labelsRow.addArrangedSubview(highL)

        // Thanks state container (hidden initially)
        thanksContainer.translatesAutoresizingMaskIntoConstraints = false
        thanksContainer.isHidden = true
        sheet.addSubview(thanksContainer)
        let check = UILabel()
        check.text = "✓"
        check.font = .systemFont(ofSize: 48, weight: .bold)
        check.textColor = accent
        check.textAlignment = .center
        check.translatesAutoresizingMaskIntoConstraints = false
        thanksContainer.addSubview(check)
        let thx = UILabel()
        thx.text = message.thanks ?? "Thanks for the feedback!"
        thx.textColor = UIColor(white: 0.96, alpha: 1)
        thx.font = .systemFont(ofSize: 16, weight: .semibold)
        thx.textAlignment = .center
        thx.numberOfLines = 0
        thx.translatesAutoresizingMaskIntoConstraints = false
        thanksContainer.addSubview(thx)

        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            sheet.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            handle.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 12),
            handle.centerXAnchor.constraint(equalTo: sheet.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 4),

            questionContainer.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 16),
            questionContainer.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 20),
            questionContainer.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -20),
            questionContainer.bottomAnchor.constraint(equalTo: sheet.bottomAnchor, constant: -20),

            qLabel.topAnchor.constraint(equalTo: questionContainer.topAnchor),
            qLabel.leadingAnchor.constraint(equalTo: questionContainer.leadingAnchor),
            qLabel.trailingAnchor.constraint(equalTo: questionContainer.trailingAnchor),

            scoreRow.topAnchor.constraint(equalTo: qLabel.bottomAnchor, constant: 18),
            scoreRow.leadingAnchor.constraint(equalTo: questionContainer.leadingAnchor),
            scoreRow.trailingAnchor.constraint(equalTo: questionContainer.trailingAnchor),

            labelsRow.topAnchor.constraint(equalTo: scoreRow.bottomAnchor, constant: 10),
            labelsRow.leadingAnchor.constraint(equalTo: questionContainer.leadingAnchor),
            labelsRow.trailingAnchor.constraint(equalTo: questionContainer.trailingAnchor),
            labelsRow.bottomAnchor.constraint(equalTo: questionContainer.bottomAnchor),

            thanksContainer.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 16),
            thanksContainer.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 20),
            thanksContainer.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -20),
            thanksContainer.bottomAnchor.constraint(equalTo: sheet.bottomAnchor, constant: -20),

            check.topAnchor.constraint(equalTo: thanksContainer.topAnchor, constant: 12),
            check.centerXAnchor.constraint(equalTo: thanksContainer.centerXAnchor),

            thx.topAnchor.constraint(equalTo: check.bottomAnchor, constant: 12),
            thx.leadingAnchor.constraint(equalTo: thanksContainer.leadingAnchor),
            thx.trailingAnchor.constraint(equalTo: thanksContainer.trailingAnchor),
            thx.bottomAnchor.constraint(equalTo: thanksContainer.bottomAnchor, constant: -12),
        ])

        // Tap-to-dismiss outside sheet
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTap))
        view.addGestureRecognizer(tap)
    }

    @objc private func scoreTapped(_ sender: UIButton) {
        guard !hasSubmitted else { return }
        hasSubmitted = true
        let score = sender.tag
        Dijji.track("__dijji_nps_submitted", properties: [
            "message_id": message.id,
            "score": score,
        ])
        questionContainer.isHidden = true
        thanksContainer.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self = self else { return }
            self.dismiss(animated: true) { self.onDismiss(.ctaTapped) }
        }
    }

    @objc private func backgroundTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: view)
        // Only dismiss if tap was outside any sheet element
        for sub in view.subviews where sub.frame.contains(p) {
            return
        }
        dismiss(animated: true) { self.onDismiss(.userClosed) }
    }
}

// MARK: - Reactions — emoji feedback bar

enum ReactionsPresenter {
    static func present(
        message: DijjiMessage,
        on host: UIViewController,
        onDismiss: @escaping (MessageHost.DismissReason) -> Void
    ) {
        let vc = ReactionsViewController(message: message, onDismiss: onDismiss)
        vc.modalPresentationStyle = .overFullScreen
        vc.modalTransitionStyle = .coverVertical
        host.present(vc, animated: true)
    }
}

private final class ReactionsViewController: UIViewController {
    private let message: DijjiMessage
    private let onDismiss: (MessageHost.DismissReason) -> Void
    private var picked: Bool = false
    private let questionContainer = UIView()
    private let thanksContainer = UIView()
    private let pickedEmojiLabel = UILabel()

    init(message: DijjiMessage, onDismiss: @escaping (MessageHost.DismissReason) -> Void) {
        self.message = message
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        let rgb = DijjiTheme.color(for: message.theme)
        let accent = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)

        let sheet = UIView()
        sheet.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1)
        sheet.layer.cornerRadius = 20
        sheet.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheet)

        let handle = UIView()
        handle.backgroundColor = UIColor(white: 0.3, alpha: 1)
        handle.layer.cornerRadius = 2
        handle.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(handle)

        // Question state
        questionContainer.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(questionContainer)

        let qLabel = UILabel()
        qLabel.text = message.question ?? "How was that?"
        qLabel.textColor = UIColor(white: 0.96, alpha: 1)
        qLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        qLabel.numberOfLines = 0
        qLabel.textAlignment = .center
        qLabel.translatesAutoresizingMaskIntoConstraints = false
        questionContainer.addSubview(qLabel)

        let emojis = (message.emojis?.isEmpty == false ? message.emojis! : ["😍","🙂","😐","😕"])

        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .equalSpacing
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        questionContainer.addSubview(row)

        for (idx, emoji) in emojis.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(emoji, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 38)
            btn.tag = idx
            btn.addTarget(self, action: #selector(emojiTapped(_:)), for: .touchUpInside)
            row.addArrangedSubview(btn)
        }

        // Thanks state
        thanksContainer.translatesAutoresizingMaskIntoConstraints = false
        thanksContainer.isHidden = true
        sheet.addSubview(thanksContainer)

        pickedEmojiLabel.font = .systemFont(ofSize: 56)
        pickedEmojiLabel.textAlignment = .center
        pickedEmojiLabel.translatesAutoresizingMaskIntoConstraints = false
        thanksContainer.addSubview(pickedEmojiLabel)

        let thx = UILabel()
        thx.text = message.thanks ?? "Thanks 🙏"
        thx.textColor = accent
        thx.font = .systemFont(ofSize: 14, weight: .semibold)
        thx.textAlignment = .center
        thx.translatesAutoresizingMaskIntoConstraints = false
        thanksContainer.addSubview(thx)

        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            sheet.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            handle.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 12),
            handle.centerXAnchor.constraint(equalTo: sheet.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 4),

            questionContainer.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 16),
            questionContainer.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 20),
            questionContainer.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -20),
            questionContainer.bottomAnchor.constraint(equalTo: sheet.bottomAnchor, constant: -22),

            qLabel.topAnchor.constraint(equalTo: questionContainer.topAnchor),
            qLabel.leadingAnchor.constraint(equalTo: questionContainer.leadingAnchor),
            qLabel.trailingAnchor.constraint(equalTo: questionContainer.trailingAnchor),

            row.topAnchor.constraint(equalTo: qLabel.bottomAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: questionContainer.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: questionContainer.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: questionContainer.bottomAnchor),

            thanksContainer.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 8),
            thanksContainer.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 20),
            thanksContainer.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -20),
            thanksContainer.bottomAnchor.constraint(equalTo: sheet.bottomAnchor, constant: -22),

            pickedEmojiLabel.topAnchor.constraint(equalTo: thanksContainer.topAnchor, constant: 8),
            pickedEmojiLabel.centerXAnchor.constraint(equalTo: thanksContainer.centerXAnchor),

            thx.topAnchor.constraint(equalTo: pickedEmojiLabel.bottomAnchor, constant: 10),
            thx.leadingAnchor.constraint(equalTo: thanksContainer.leadingAnchor),
            thx.trailingAnchor.constraint(equalTo: thanksContainer.trailingAnchor),
            thx.bottomAnchor.constraint(equalTo: thanksContainer.bottomAnchor, constant: -10),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTap))
        view.addGestureRecognizer(tap)
    }

    @objc private func emojiTapped(_ sender: UIButton) {
        guard !picked else { return }
        picked = true
        let idx = sender.tag
        let emoji = sender.titleLabel?.text ?? ""
        Dijji.track("__dijji_reaction_submitted", properties: [
            "message_id": message.id,
            "reaction": emoji,
            "index": idx,
        ])
        pickedEmojiLabel.text = emoji
        questionContainer.isHidden = true
        thanksContainer.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self = self else { return }
            self.dismiss(animated: true) { self.onDismiss(.ctaTapped) }
        }
    }

    @objc private func backgroundTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: view)
        for sub in view.subviews where sub.frame.contains(p) { return }
        dismiss(animated: true) { self.onDismiss(.userClosed) }
    }
}

// MARK: - Countdown — live ticker urgency modal

enum CountdownPresenter {
    static func present(
        message: DijjiMessage,
        on host: UIViewController,
        onDismiss: @escaping (MessageHost.DismissReason) -> Void
    ) {
        guard let deadline = message.parsedDeadline else {
            // Drop the message rather than render a broken timer
            onDismiss(.autoExpired)
            return
        }
        let vc = CountdownViewController(message: message, deadline: deadline, onDismiss: onDismiss)
        vc.modalPresentationStyle = .overFullScreen
        vc.modalTransitionStyle = .crossDissolve
        host.present(vc, animated: true)
    }
}

private final class CountdownViewController: UIViewController {
    private let message: DijjiMessage
    private let deadline: Date
    private let onDismiss: (MessageHost.DismissReason) -> Void
    private var timer: Timer?
    private let dCell = makeCell()
    private let hCell = makeCell()
    private let mCell = makeCell()
    private let sCell = makeCell()
    private let endedLabel = UILabel()
    private let timerStack = UIStackView()
    private var ctaBtn: UIButton?

    init(message: DijjiMessage, deadline: Date, onDismiss: @escaping (MessageHost.DismissReason) -> Void) {
        self.message = message
        self.deadline = deadline
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func makeCell() -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        let rgb = DijjiTheme.color(for: message.theme)
        let accent = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)

        let card = UIView()
        card.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1)
        card.layer.cornerRadius = 20
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        let inner = UIStackView()
        inner.axis = .vertical
        inner.alignment = .fill
        inner.spacing = 16
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)

        if let imgUrl = message.imageUrl, !imgUrl.isEmpty {
            let imgView = UIImageView()
            imgView.contentMode = .scaleAspectFill
            imgView.clipsToBounds = true
            imgView.translatesAutoresizingMaskIntoConstraints = false
            imgView.heightAnchor.constraint(equalTo: imgView.widthAnchor, multiplier: 9.0/16.0).isActive = true
            DijjiImageLoader.load(imgUrl, into: imgView)
            inner.addArrangedSubview(imgView)
        }

        if let t = message.title, !t.isEmpty {
            let l = UILabel()
            l.text = t
            l.textColor = UIColor(white: 0.96, alpha: 1)
            l.font = .systemFont(ofSize: 20, weight: .bold)
            l.textAlignment = .center
            l.numberOfLines = 0
            inner.addArrangedSubview(l)
        }

        // Timer row
        timerStack.axis = .horizontal
        timerStack.alignment = .center
        timerStack.distribution = .equalSpacing
        timerStack.spacing = 6
        for cellView in [dCell, hCell, mCell, sCell] {
            buildCellSubviews(cellView, accent: accent)
            timerStack.addArrangedSubview(cellView)
            if cellView !== sCell {
                let colon = UILabel()
                colon.text = ":"
                colon.textColor = UIColor(white: 0.3, alpha: 1)
                colon.font = .systemFont(ofSize: 22, weight: .bold)
                timerStack.addArrangedSubview(colon)
            }
        }
        let timerWrap = UIView()
        timerWrap.translatesAutoresizingMaskIntoConstraints = false
        timerStack.translatesAutoresizingMaskIntoConstraints = false
        timerWrap.addSubview(timerStack)
        NSLayoutConstraint.activate([
            timerStack.centerXAnchor.constraint(equalTo: timerWrap.centerXAnchor),
            timerStack.topAnchor.constraint(equalTo: timerWrap.topAnchor),
            timerStack.bottomAnchor.constraint(equalTo: timerWrap.bottomAnchor),
        ])
        inner.addArrangedSubview(timerWrap)

        endedLabel.text = message.endedText ?? "Time's up."
        endedLabel.textColor = UIColor(red: 0.90, green: 0.45, blue: 0.45, alpha: 1)
        endedLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        endedLabel.textAlignment = .center
        endedLabel.numberOfLines = 0
        endedLabel.isHidden = true
        inner.addArrangedSubview(endedLabel)

        if let b = message.body, !b.isEmpty {
            let l = UILabel()
            l.text = b
            l.textColor = UIColor(red: 0.71, green: 0.71, blue: 0.78, alpha: 1)
            l.font = .systemFont(ofSize: 14.5)
            l.numberOfLines = 0
            l.textAlignment = .center
            inner.addArrangedSubview(l)
        }

        if let c = message.ctaText, !c.isEmpty {
            let btn = UIButton(type: .system)
            btn.setTitle(c, for: .normal)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = accent
            btn.layer.cornerRadius = 10
            btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            btn.heightAnchor.constraint(equalToConstant: 52).isActive = true
            btn.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)
            ctaBtn = btn
            inner.addArrangedSubview(btn)
        }

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 420),

            inner.topAnchor.constraint(equalTo: card.topAnchor),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
        ])
        // Pad inner content (image goes flush, others get inset)
        inner.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 0, right: 24)
        inner.isLayoutMarginsRelativeArrangement = true

        startTicker()
    }

    private func buildCellSubviews(_ cell: UIView, accent: UIColor) {
        let valueLabel = UILabel()
        valueLabel.tag = 1
        valueLabel.textColor = accent
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        valueLabel.textAlignment = .center
        valueLabel.text = "00"
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.backgroundColor = accent.withAlphaComponent(0.12)
        valueLabel.layer.cornerRadius = 8
        valueLabel.clipsToBounds = true
        valueLabel.layer.borderWidth = 1
        valueLabel.layer.borderColor = accent.withAlphaComponent(0.4).cgColor
        cell.addSubview(valueLabel)

        let unitLabel = UILabel()
        unitLabel.tag = 2
        unitLabel.textColor = UIColor(white: 0.5, alpha: 1)
        unitLabel.font = .systemFont(ofSize: 10)
        unitLabel.textAlignment = .center
        unitLabel.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(unitLabel)

        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: cell.topAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            valueLabel.heightAnchor.constraint(equalToConstant: 48),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),

            unitLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 4),
            unitLabel.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            unitLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            unitLabel.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
        ])
    }

    private func startTicker() {
        (dCell.viewWithTag(2) as? UILabel)?.text = "d"
        (hCell.viewWithTag(2) as? UILabel)?.text = "h"
        (mCell.viewWithTag(2) as? UILabel)?.text = "m"
        (sCell.viewWithTag(2) as? UILabel)?.text = "s"
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            timerStack.isHidden = true
            endedLabel.isHidden = false
            ctaBtn?.isEnabled = false
            ctaBtn?.alpha = 0.4
            timer?.invalidate()
            timer = nil
            return
        }
        let total = Int(remaining)
        let days = total / 86400
        let hours = (total / 3600) % 24
        let mins  = (total / 60) % 60
        let secs  = total % 60
        (dCell.viewWithTag(1) as? UILabel)?.text = "\(days)"
        dCell.isHidden = (days == 0)
        (hCell.viewWithTag(1) as? UILabel)?.text = String(format: "%02d", hours)
        (mCell.viewWithTag(1) as? UILabel)?.text = String(format: "%02d", mins)
        (sCell.viewWithTag(1) as? UILabel)?.text = String(format: "%02d", secs)
    }

    @objc private func ctaTapped() {
        Dijji.track("__dijji_message_clicked", properties: [
            "message_id": message.id,
            "kind": message.kind.rawValue,
            "cta_url": message.ctaUrl ?? "",
        ])
        if let raw = message.ctaUrl, let url = URL(string: raw) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        dismiss(animated: true) { self.onDismiss(.ctaTapped) }
    }

    deinit {
        timer?.invalidate()
    }
}
#endif
