#if canImport(UIKit)
import UIKit
import DijjiCore

/// Bottom-sheet survey renderer — multi-question form with progress bar,
/// per-question types (rating / radio / checkbox / yesno / text), and a
/// configurable end screen (thanks / cta / share / nothing).
///
/// Wire format mirrors the Flutter SDK's _SurveyWidget (lib/src/messages.dart).
/// Per-answer POSTs fire as the user advances; a final `complete` POST
/// marks end-screen-seen on the server.
enum SurveyPresenter {
    static func present(
        message: DijjiMessage,
        on host: UIViewController,
        onDismiss: @escaping (MessageHost.DismissReason) -> Void
    ) {
        let vc = SurveyViewController(message: message, onDismiss: onDismiss)
        vc.modalPresentationStyle = .overFullScreen
        vc.modalTransitionStyle = .crossDissolve
        host.present(vc, animated: true)
    }
}

private final class SurveyViewController: UIViewController {

    // MARK: - Static palette

    /// Accent purple — matches the Flutter renderer + tracker. Same hex
    /// (#7C3AED) regardless of `theme` config; the survey UI is
    /// intentionally consistent across customers' brand colors.
    private static let accent = UIColor(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255, alpha: 1)
    private static let danger = UIColor(red: 0xEF/255, green: 0x44/255, blue: 0x44/255, alpha: 1)
    private static let textPrimary = UIColor(red: 0x0F/255, green: 0x17/255, blue: 0x2A/255, alpha: 1)
    private static let neutralBg = UIColor(red: 0xE2/255, green: 0xE8/255, blue: 0xF0/255, alpha: 1)

    // MARK: - Inputs

    private let message: DijjiMessage
    private let onDismiss: (MessageHost.DismissReason) -> Void
    private let surveyId: Int
    private let responseId: Int
    private let questions: [[String: Any]]
    private let endScreen: [String: Any]

    // MARK: - State

    private var step: Int = 0
    private var answers: [String: Any] = [:]
    private var completed: Bool = false
    private var dismissed: Bool = false

    // MARK: - Views

    private let card = UIView()
    private var cardBottomConstraint: NSLayoutConstraint?
    private let dragHandle = UIView()
    private let progressRow = UIStackView()
    private let contentScroll = UIScrollView()
    private let contentStack = UIStackView()
    private let footerRow = UIStackView()
    private let backButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)

    // MARK: - Init

    init(message: DijjiMessage, onDismiss: @escaping (MessageHost.DismissReason) -> Void) {
        self.message = message
        self.onDismiss = onDismiss
        let cfg = message.rawConfig
        let sid: Int
        if let n = cfg["survey_id"] as? Int { sid = n }
        else if let n = cfg["survey_id"] as? NSNumber { sid = n.intValue }
        else { sid = 0 }
        self.surveyId = sid
        let rid: Int
        if let n = cfg["response_id"] as? Int { rid = n }
        else if let n = cfg["response_id"] as? NSNumber { rid = n.intValue }
        else { rid = 0 }
        self.responseId = rid
        self.questions = (cfg["questions"] as? [[String: Any]]) ?? []
        self.endScreen = (cfg["end_screen"] as? [String: Any]) ?? ["type": "thanks"]
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0)
        buildBackdrop()
        buildCard()
        buildHandle()
        buildProgressRow()
        buildContentScroll()
        buildFooter()
        layoutAll()
        renderCurrent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.35) {
            self.cardBottomConstraint?.constant = 0
            self.view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Build steps

    private func buildBackdrop() {
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
    }

    private func buildCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.systemBackground
        card.layer.cornerRadius = 16
        card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.18
        card.layer.shadowRadius = 24
        card.layer.shadowOffset = CGSize(width: 0, height: -4)
        view.addSubview(card)
        // Drag-to-dismiss
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        card.addGestureRecognizer(pan)
    }

    private func buildHandle() {
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        dragHandle.backgroundColor = Self.neutralBg
        dragHandle.layer.cornerRadius = 2
        card.addSubview(dragHandle)
    }

    private func buildProgressRow() {
        progressRow.axis = .horizontal
        progressRow.alignment = .fill
        progressRow.distribution = .fillEqually
        progressRow.spacing = 4
        progressRow.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(progressRow)
        for _ in 0..<questions.count {
            let seg = UIView()
            seg.layer.cornerRadius = 1.5
            seg.heightAnchor.constraint(equalToConstant: 3).isActive = true
            progressRow.addArrangedSubview(seg)
        }
    }

    private func buildContentScroll() {
        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.alwaysBounceVertical = true
        contentScroll.showsVerticalScrollIndicator = false
        card.addSubview(contentScroll)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.addSubview(contentStack)
    }

    private func buildFooter() {
        footerRow.axis = .horizontal
        footerRow.alignment = .center
        footerRow.distribution = .equalSpacing
        footerRow.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(footerRow)

        backButton.setTitle("Back", for: .normal)
        backButton.setTitleColor(Self.textPrimary.withAlphaComponent(0.7), for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        backButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        nextButton.setTitle("Next", for: .normal)
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        nextButton.backgroundColor = Self.accent
        nextButton.layer.cornerRadius = 8
        nextButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        footerRow.addArrangedSubview(backButton)
        footerRow.addArrangedSubview(nextButton)
    }

    private func layoutAll() {
        cardBottomConstraint = card.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 600)
        cardBottomConstraint?.isActive = true
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Keep the survey from filling the whole screen — leaves a tap
            // strip at the top so users can dismiss without scrolling.
            card.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.85),

            dragHandle.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            dragHandle.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 36),
            dragHandle.heightAnchor.constraint(equalToConstant: 4),

            progressRow.topAnchor.constraint(equalTo: dragHandle.bottomAnchor, constant: 14),
            progressRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            progressRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),

            contentScroll.topAnchor.constraint(equalTo: progressRow.bottomAnchor, constant: 16),
            contentScroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            contentScroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),

            contentStack.topAnchor.constraint(equalTo: contentScroll.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: contentScroll.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentScroll.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: contentScroll.bottomAnchor),
            // Width pin so the inner stack doesn't collapse to zero width
            // inside the scroll view's flexible content size.
            contentStack.widthAnchor.constraint(equalTo: contentScroll.widthAnchor),

            footerRow.topAnchor.constraint(equalTo: contentScroll.bottomAnchor, constant: 16),
            footerRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            footerRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            footerRow.bottomAnchor.constraint(equalTo: card.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Render — repaints content + progress + footer for current step

    private func renderCurrent() {
        // Clear then rebuild — simple + correct, avoids tracking per-cell
        // state. The form is small (1..N questions) so the rebuild cost
        // is negligible.
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Progress segments
        for (i, seg) in progressRow.arrangedSubviews.enumerated() {
            if i < step {
                seg.backgroundColor = Self.accent
            } else if i == step {
                seg.backgroundColor = Self.accent.withAlphaComponent(0.6)
            } else {
                seg.backgroundColor = Self.neutralBg
            }
        }

        if completed {
            progressRow.isHidden = true
            footerRow.isHidden = true
            buildEndScreen()
            return
        }

        progressRow.isHidden = false
        footerRow.isHidden = false

        guard step >= 0, step < questions.count else { return }
        let q = questions[step]
        let label = (q["label"] as? String) ?? ""
        let required = (q["required"] as? Bool) ?? false

        // Question label with optional red asterisk
        let labelView = UILabel()
        labelView.numberOfLines = 0
        let attr = NSMutableAttributedString(
            string: label,
            attributes: [
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: Self.textPrimary,
            ]
        )
        if required {
            attr.append(NSAttributedString(
                string: " *",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                    .foregroundColor: Self.danger,
                ]
            ))
        }
        labelView.attributedText = attr
        contentStack.addArrangedSubview(labelView)

        contentStack.addArrangedSubview(buildQuestionBody(q))

        // Footer
        backButton.isHidden = (step == 0)
        nextButton.setTitle(step == questions.count - 1 ? "Submit" : "Next", for: .normal)
        updateNextEnabled()
    }

    private func buildQuestionBody(_ q: [String: Any]) -> UIView {
        let type = (q["type"] as? String) ?? ""
        let qid = (q["id"] as? String) ?? ""

        switch type {
        case "rating":   return buildRatingBody(q, qid: qid)
        case "radio":    return buildRadioBody(q, qid: qid)
        case "checkbox": return buildCheckboxBody(q, qid: qid)
        case "yesno":    return buildYesNoBody(qid: qid)
        default:         return buildTextBody(qid: qid)  // fallthrough = text
        }
    }

    // MARK: - Question bodies

    private func buildRatingBody(_ q: [String: Any], qid: String) -> UIView {
        let rmaxAny = q["rating_max"]
        let rmax: Int
        if let n = rmaxAny as? Int { rmax = n }
        else if let n = rmaxAny as? NSNumber { rmax = n.intValue }
        else { rmax = 5 }
        let start = (rmax == 10 ? 0 : 1)
        let selected = answers[qid] as? Int

        // Wrap row: stack rows of up to 6 buttons each so 0–10 doesn't
        // overflow on narrow screens. UIStackView nesting keeps it simple.
        let outer = UIStackView()
        outer.axis = .vertical
        outer.spacing = 6
        outer.alignment = .leading

        var current = makeRatingRow()
        outer.addArrangedSubview(current)
        var inRow = 0
        let perRow = 6

        for v in start...rmax {
            if inRow == perRow {
                current = makeRatingRow()
                outer.addArrangedSubview(current)
                inRow = 0
            }
            let btn = makeRatingButton(value: v, selected: selected == v, qid: qid)
            current.addArrangedSubview(btn)
            inRow += 1
        }
        return outer
    }

    private func makeRatingRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        return row
    }

    private func makeRatingButton(value: Int, selected: Bool, qid: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle("\(value)", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        btn.layer.cornerRadius = 8
        btn.layer.borderWidth = 1
        if selected {
            btn.backgroundColor = Self.accent
            btn.setTitleColor(.white, for: .normal)
            btn.layer.borderColor = Self.accent.cgColor
        } else {
            btn.backgroundColor = UIColor(red: 0xF8/255, green: 0xFA/255, blue: 0xFC/255, alpha: 1)
            btn.setTitleColor(Self.textPrimary, for: .normal)
            btn.layer.borderColor = Self.neutralBg.cgColor
        }
        btn.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        btn.tag = value
        btn.accessibilityIdentifier = qid
        btn.addTarget(self, action: #selector(ratingTapped(_:)), for: .touchUpInside)
        return btn
    }

    private func buildRadioBody(_ q: [String: Any], qid: String) -> UIView {
        let choices = (q["choices"] as? [String]) ?? []
        let selected = answers[qid] as? String
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        for c in choices {
            let tile = makeChoiceTile(label: c, selected: selected == c, multi: false, qid: qid)
            stack.addArrangedSubview(tile)
        }
        return stack
    }

    private func buildCheckboxBody(_ q: [String: Any], qid: String) -> UIView {
        let choices = (q["choices"] as? [String]) ?? []
        let picked = (answers[qid] as? [String]) ?? []
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        for c in choices {
            let tile = makeChoiceTile(label: c, selected: picked.contains(c), multi: true, qid: qid)
            stack.addArrangedSubview(tile)
        }
        return stack
    }

    private func makeChoiceTile(label: String, selected: Bool, multi: Bool, qid: String) -> UIView {
        let tile = UIControl()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.backgroundColor = selected
            ? Self.accent.withAlphaComponent(0.08)
            : UIColor(red: 0xF8/255, green: 0xFA/255, blue: 0xFC/255, alpha: 1)
        tile.layer.cornerRadius = 8
        tile.layer.borderWidth = 1.2
        tile.layer.borderColor = (selected ? Self.accent : Self.neutralBg).cgColor
        tile.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        tile.accessibilityIdentifier = qid
        tile.accessibilityLabel = label
        tile.accessibilityValue = (multi ? "checkbox" : "radio")
        tile.addTarget(self, action: #selector(choiceTileTapped(_:)), for: .touchUpInside)

        let lbl = UILabel()
        lbl.text = label
        lbl.font = .systemFont(ofSize: 15, weight: .medium)
        lbl.textColor = Self.textPrimary
        lbl.numberOfLines = 0
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.isUserInteractionEnabled = false
        tile.addSubview(lbl)

        let mark = UILabel()
        mark.text = selected ? (multi ? "✓" : "●") : ""
        mark.font = .systemFont(ofSize: 16, weight: .bold)
        mark.textColor = Self.accent
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.isUserInteractionEnabled = false
        tile.addSubview(mark)

        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 14),
            lbl.topAnchor.constraint(equalTo: tile.topAnchor, constant: 12),
            lbl.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -12),
            lbl.trailingAnchor.constraint(lessThanOrEqualTo: mark.leadingAnchor, constant: -12),

            mark.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -14),
            mark.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 22),
        ])
        return tile
    }

    private func buildYesNoBody(qid: String) -> UIView {
        let selected = answers[qid] as? Int
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fillEqually
        row.spacing = 10

        let yes = makeYesNoButton(label: "Yes", selected: selected == 1, kind: "yes", qid: qid)
        let no  = makeYesNoButton(label: "No",  selected: selected == 0, kind: "no",  qid: qid)
        row.addArrangedSubview(yes)
        row.addArrangedSubview(no)
        return row
    }

    private func makeYesNoButton(label: String, selected: Bool, kind: String, qid: String) -> UIControl {
        let tile = UIControl()
        tile.translatesAutoresizingMaskIntoConstraints = false
        let positive = (kind == "yes")
        let pickedColor = positive
            ? UIColor(red: 0x05/255, green: 0x96/255, blue: 0x69/255, alpha: 1)   // emerald
            : UIColor(red: 0xE1/255, green: 0x1D/255, blue: 0x48/255, alpha: 1)   // rose
        if selected {
            tile.backgroundColor = pickedColor.withAlphaComponent(0.10)
            tile.layer.borderColor = pickedColor.cgColor
        } else {
            tile.backgroundColor = UIColor(red: 0xF8/255, green: 0xFA/255, blue: 0xFC/255, alpha: 1)
            tile.layer.borderColor = Self.neutralBg.cgColor
        }
        tile.layer.cornerRadius = 8
        tile.layer.borderWidth = 1.2
        tile.heightAnchor.constraint(equalToConstant: 56).isActive = true
        tile.accessibilityIdentifier = qid
        tile.accessibilityLabel = kind
        tile.addTarget(self, action: #selector(yesNoTapped(_:)), for: .touchUpInside)

        let lbl = UILabel()
        lbl.text = label
        lbl.font = .systemFont(ofSize: 16, weight: .semibold)
        lbl.textColor = selected ? pickedColor : Self.textPrimary
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.isUserInteractionEnabled = false
        tile.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
        ])
        return tile
    }

    private func buildTextBody(qid: String) -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.layer.borderColor = Self.neutralBg.cgColor
        wrap.layer.borderWidth = 1
        wrap.layer.cornerRadius = 8

        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.font = .systemFont(ofSize: 15)
        tv.backgroundColor = .clear
        tv.textColor = Self.textPrimary
        tv.text = (answers[qid] as? String) ?? ""
        tv.delegate = self
        tv.accessibilityIdentifier = qid
        tv.tag = step  // marker so the delegate can recover qid via accessibilityIdentifier
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        wrap.addSubview(tv)

        // Visible-line height target ≈ 4 lines.
        let h = tv.heightAnchor.constraint(equalToConstant: 96)
        h.priority = .defaultHigh
        h.isActive = true

        // Hint placeholder — UITextView has no native placeholder. Wire
        // a faint label that hides while text is non-empty.
        let placeholder = UILabel()
        placeholder.text = "Tell us..."
        placeholder.font = .systemFont(ofSize: 15)
        placeholder.textColor = Self.textPrimary.withAlphaComponent(0.35)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.tag = 999
        placeholder.isHidden = !tv.text.isEmpty
        wrap.addSubview(placeholder)

        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: wrap.topAnchor),
            tv.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            tv.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            placeholder.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 12),
        ])
        return wrap
    }

    // MARK: - End screen

    private func buildEndScreen() {
        let endType = (endScreen["type"] as? String) ?? "thanks"
        let thanks  = (endScreen["thanks_text"] as? String) ?? "Thanks for your feedback!"
        let ctaText = (endScreen["cta_text"] as? String) ?? "Learn more"
        let ctaUrl  = endScreen["cta_url"] as? String

        let l = UILabel()
        l.text = thanks
        l.font = .systemFont(ofSize: 22, weight: .bold)
        l.textColor = Self.textPrimary
        l.textAlignment = .center
        l.numberOfLines = 0
        contentStack.addArrangedSubview(l)

        if endType == "cta", let urlStr = ctaUrl, !urlStr.isEmpty {
            let btn = UIButton(type: .system)
            btn.setTitle(ctaText, for: .normal)
            btn.setTitleColor(.white, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            btn.backgroundColor = Self.accent
            btn.layer.cornerRadius = 10
            btn.contentEdgeInsets = UIEdgeInsets(top: 12, left: 22, bottom: 12, right: 22)
            btn.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            btn.accessibilityIdentifier = urlStr
            btn.addTarget(self, action: #selector(endCtaTapped(_:)), for: .touchUpInside)

            // Centre via a wrapper since the contentStack is fillEqually-fill.
            let wrap = UIView()
            wrap.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(btn)
            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 12),
                btn.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
                btn.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            ])
            contentStack.addArrangedSubview(wrap)
        }

        // Auto-dismiss for thanks / nothing — give the user a beat to read it.
        // CTA + share keep the sheet open so they can act on it.
        if endType == "thanks" || endType == "nothing" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self = self, !self.dismissed else { return }
                self.animatedDismiss(reason: .autoExpired)
            }
        }
    }

    // MARK: - Actions

    @objc private func backTapped() {
        guard step > 0 else { return }
        step -= 1
        renderCurrent()
    }

    @objc private func nextTapped() {
        guard step < questions.count else { return }
        let q = questions[step]
        let qid = (q["id"] as? String) ?? ""
        let qtype = (q["type"] as? String) ?? ""

        // Build the wire `value` per question type — Flutter shape:
        //   text/radio/yesno/rating → String (yesno = "1"/"0", rating = "<n>")
        //   checkbox → [String]
        var wireValue: Any = ""
        let raw = answers[qid]
        if qtype == "checkbox" {
            wireValue = (raw as? [String]) ?? []
        } else if qtype == "yesno" {
            if let n = raw as? Int { wireValue = (n == 1) ? "1" : "0" } else { wireValue = "" }
        } else if qtype == "rating" {
            if let n = raw as? Int { wireValue = "\(n)" } else { wireValue = "" }
        } else {
            // text + radio + anything else → string
            if let s = raw as? String { wireValue = s }
            else if let n = raw as? Int { wireValue = "\(n)" }
            else { wireValue = "" }
        }

        if let cb = MessageHost.shared.onSurveyPost {
            let body: [String: Any] = [
                "action": "answer",
                "site": Dijji.siteKey ?? "",
                "response_id": responseId,
                "question_id": qid,
                "question_type": qtype,
                "value": wireValue,
            ]
            // Off the main thread — JSONSerialization + URLSession launching
            // shouldn't block the UI even though they're cheap.
            DispatchQueue.global().async { cb(body) }
        }

        step += 1
        if step >= questions.count {
            // End of survey — fire complete then flip to end screen.
            if let cb = MessageHost.shared.onSurveyPost {
                let body: [String: Any] = [
                    "action": "complete",
                    "site": Dijji.siteKey ?? "",
                    "response_id": responseId,
                    "end_screen_seen": 1,
                ]
                DispatchQueue.global().async { cb(body) }
            }
            completed = true
        }
        renderCurrent()
    }

    @objc private func ratingTapped(_ sender: UIButton) {
        guard step >= 0, step < questions.count else { return }
        let qid = sender.accessibilityIdentifier ?? ""
        answers[qid] = sender.tag
        renderCurrent()
    }

    @objc private func choiceTileTapped(_ sender: UIControl) {
        guard step >= 0, step < questions.count else { return }
        let qid = sender.accessibilityIdentifier ?? ""
        let label = sender.accessibilityLabel ?? ""
        let multi = (sender.accessibilityValue == "checkbox")
        if multi {
            var picked = (answers[qid] as? [String]) ?? []
            if let i = picked.firstIndex(of: label) {
                picked.remove(at: i)
            } else {
                picked.append(label)
            }
            answers[qid] = picked
        } else {
            answers[qid] = label
        }
        renderCurrent()
    }

    @objc private func yesNoTapped(_ sender: UIControl) {
        let qid = sender.accessibilityIdentifier ?? ""
        let kind = sender.accessibilityLabel ?? ""
        answers[qid] = (kind == "yes") ? 1 : 0
        renderCurrent()
    }

    @objc private func endCtaTapped(_ sender: UIButton) {
        if let raw = sender.accessibilityIdentifier, let url = URL(string: raw) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        animatedDismiss(reason: .ctaTapped)
    }

    @objc private func backdropTapped() {
        animatedDismiss(reason: .userClosed)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let translation = g.translation(in: view).y
        switch g.state {
        case .changed:
            cardBottomConstraint?.constant = max(0, translation)
        case .ended, .cancelled:
            let velocity = g.velocity(in: view).y
            if translation > 80 || velocity > 600 {
                animatedDismiss(reason: .userClosed)
            } else {
                UIView.animate(withDuration: 0.24) {
                    self.cardBottomConstraint?.constant = 0
                    self.view.layoutIfNeeded()
                }
            }
        default: break
        }
    }

    // MARK: - Helpers

    private func updateNextEnabled() {
        guard step >= 0, step < questions.count else { return }
        let q = questions[step]
        let required = (q["required"] as? Bool) ?? false
        let canAdvance = !required || hasAnswer(q)
        nextButton.isEnabled = canAdvance
        nextButton.alpha = canAdvance ? 1.0 : 0.45
    }

    private func hasAnswer(_ q: [String: Any]) -> Bool {
        let qid = (q["id"] as? String) ?? ""
        let v = answers[qid]
        if v == nil { return false }
        if let s = v as? String { return !s.trimmingCharacters(in: .whitespaces).isEmpty }
        if let l = v as? [Any] { return !l.isEmpty }
        return true
    }

    private func animatedDismiss(reason: MessageHost.DismissReason) {
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

// MARK: - UITextViewDelegate — text question editing

extension SurveyViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Hard cap at 2000 chars — matches the Flutter renderer + the
        // backend's storage column. Pasting more is silently truncated.
        let current = textView.text ?? ""
        guard let r = Range(range, in: current) else { return true }
        let updated = current.replacingCharacters(in: r, with: text)
        return updated.count <= 2000
    }

    func textViewDidChange(_ textView: UITextView) {
        let qid = textView.accessibilityIdentifier ?? ""
        answers[qid] = textView.text ?? ""

        // Toggle placeholder visibility without rebuilding the form
        // (rebuilding would steal focus from the keyboard).
        if let placeholder = textView.superview?.viewWithTag(999) as? UILabel {
            placeholder.isHidden = !(textView.text ?? "").isEmpty
        }
        updateNextEnabled()
    }
}
#endif
