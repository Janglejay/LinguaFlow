import AppKit
import LinguaFlowCore
import LinguaFlowRime

@MainActor
final class PreviewPanelController {
    enum TranslationState: Equatable {
        case hidden
        case loading
        case result(String)
        case message(String)
    }

    static let shared = PreviewPanelController()

    private let panel: NSPanel
    private let previewView: PreviewView
    private var activeOwner: ObjectIdentifier?

    private init() {
        previewView = PreviewView(frame: .zero)
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = previewView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func update(
        owner: AnyObject,
        preedit: String,
        sourceText: String?,
        candidates: [RimeCandidate],
        highlightedIndex: Int,
        translation: TranslationState,
        direction: TranslationDirection,
        spellingCorrection: EnglishSpellingCorrection?
    ) {
        activeOwner = ObjectIdentifier(owner)
        previewView.update(
            preedit: preedit,
            sourceText: sourceText,
            candidates: Array(candidates.prefix(5)),
            highlightedIndex: highlightedIndex,
            translation: translation,
            direction: direction,
            spellingCorrection: spellingCorrection
        )

        let size = previewView.preferredSize
        if panel.frame.size != size {
            panel.setContentSize(size)
        }
    }

    func show(owner: AnyObject, near anchor: NSRect, clientWindowLevel: CGWindowLevel?) {
        guard activeOwner == ObjectIdentifier(owner) else { return }

        if let clientWindowLevel {
            panel.level = NSWindow.Level(rawValue: Int(clientWindowLevel) + 1)
        }

        let visibleFrame = NSScreen.screens
            .first(where: { $0.frame.intersects(anchor) })?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = UnifiedPanelLayout.origin(
            anchor: anchor,
            panelSize: previewView.preferredSize,
            visibleFrame: visibleFrame
        )

        if abs(panel.frame.origin.x - origin.x) > 0.5
            || abs(panel.frame.origin.y - origin.y) > 0.5
        {
            panel.setFrameOrigin(origin)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide(owner: AnyObject) {
        guard activeOwner == nil || activeOwner == ObjectIdentifier(owner) else { return }
        panel.orderOut(nil)
        activeOwner = nil
    }
}

@MainActor
private final class PreviewView: NSView {
    private(set) var preferredSize = NSSize(width: 220, height: 48)
    private var preedit = ""
    private var sourceText: String?
    private var candidates: [RimeCandidate] = []
    private var highlightedIndex = 0
    private var translation: PreviewPanelController.TranslationState = .hidden
    private var direction = TranslationDirection.chineseToEnglish
    private var spellingCorrection: EnglishSpellingCorrection?

    private let regularFont = NSFont.systemFont(ofSize: 14)
    private let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    private let shortcutFont = NSFont.systemFont(ofSize: 10)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("LinguaFlow 输入、纠错与翻译预览")
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        preedit: String,
        sourceText: String?,
        candidates: [RimeCandidate],
        highlightedIndex: Int,
        translation: PreviewPanelController.TranslationState,
        direction: TranslationDirection,
        spellingCorrection: EnglishSpellingCorrection?
    ) {
        let changed = self.preedit != preedit
            || self.sourceText != sourceText
            || self.candidates != candidates
            || self.highlightedIndex != highlightedIndex
            || self.translation != translation
            || self.direction != direction
            || self.spellingCorrection != spellingCorrection

        self.preedit = preedit
        self.sourceText = sourceText
        self.candidates = candidates
        self.highlightedIndex = highlightedIndex
        self.translation = translation
        self.direction = direction
        self.spellingCorrection = spellingCorrection
        preferredSize = calculateSize()
        frame.size = preferredSize
        if changed {
            needsDisplay = true
            setAccessibilityValue(accessibilityText)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor.windowBackgroundColor.withAlphaComponent(0.98).setFill()
        background.fill()
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        background.lineWidth = 0.5
        background.stroke()

        var y = UnifiedPanelLayout.verticalPadding
        if let header = headerContent {
            drawLabeledText(label: header.label, value: header.value, y: y)
            y += 20 + UnifiedPanelLayout.rowSpacing
        }

        if !candidates.isEmpty {
            drawCandidates(y: y)
            y += candidateRowHeight + UnifiedPanelLayout.rowSpacing
        }

        if let spellingCorrection {
            drawCorrection(spellingCorrection, y: y)
            y += 20 + UnifiedPanelLayout.rowSpacing
        }

        if translation != .hidden {
            if headerContent != nil || !candidates.isEmpty || spellingCorrection != nil {
                NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
                let divider = NSBezierPath()
                divider.move(to: NSPoint(x: 10, y: y - 2))
                divider.line(to: NSPoint(x: bounds.width - 10, y: y - 2))
                divider.lineWidth = 0.5
                divider.stroke()
            }
            drawTranslation(y: y)
        }
    }

    private var headerContent: (label: String, value: String)? {
        if !preedit.isEmpty {
            return ("拼音", preedit)
        }
        if let sourceText, !sourceText.isEmpty {
            return (direction.sourceLabel, sourceText)
        }
        return nil
    }

    private var translationText: String? {
        switch translation {
        case .hidden:
            nil
        case .loading:
            direction == .chineseToEnglish ? "正在生成英文…" : "正在生成中文…"
        case .result(let value), .message(let value):
            value
        }
    }

    private func calculateSize() -> NSSize {
        var widths: [CGFloat] = []
        var rowHeights: [CGFloat] = []

        if let header = headerContent {
            widths.append(labeledTextWidth(label: header.label, value: header.value))
            rowHeights.append(20)
        }
        if !candidates.isEmpty {
            widths.append(candidateRowWidth)
            rowHeights.append(candidateRowHeight)
        }
        if let spellingCorrection {
            widths.append(
                labeledTextWidth(
                    label: "纠错",
                    value: "\(spellingCorrection.original) → \(spellingCorrection.replacement)   Tab 接受"
                )
            )
            rowHeights.append(20)
        }
        if let translationText {
            widths.append(labeledTextWidth(label: direction.targetLabel, value: translationText))
            let provisionalSize = UnifiedPanelLayout.size(
                contentWidths: widths,
                rowHeights: rowHeights + [20]
            )
            let availableTextWidth = provisionalSize.width
                - UnifiedPanelLayout.horizontalPadding * 2
                - 34
            var height = max(20, textHeight(translationText, width: availableTextWidth))
            if case .result = translation {
                widths.append(textWidth("⌃↩ 插入英文   ⇧⌃↩ 换行插入", font: shortcutFont) + 34)
                height += 16
            }
            rowHeights.append(height)
        }

        return UnifiedPanelLayout.size(contentWidths: widths, rowHeights: rowHeights)
    }

    private func drawLabeledText(label: String, value: String, y: CGFloat) {
        drawText(
            label,
            in: NSRect(x: 12, y: y + 2, width: 30, height: 18),
            color: .secondaryLabelColor,
            font: labelFont,
            lineBreakMode: .byClipping
        )
        drawText(
            value,
            in: NSRect(x: 46, y: y, width: bounds.width - 58, height: 20),
            color: .labelColor,
            font: regularFont,
            lineBreakMode: .byTruncatingTail
        )
    }

    private func drawCandidates(y: CGFloat) {
        var x = UnifiedPanelLayout.horizontalPadding
        var rowY = y
        let maximumX = bounds.width - UnifiedPanelLayout.horizontalPadding
        for (index, candidate) in candidates.enumerated() {
            let title = candidateTitle(at: index, candidate: candidate)
            let naturalWidth = candidateWidth(at: index, candidate: candidate)
            let width = min(naturalWidth, maximumCandidateContentWidth)
            if x > UnifiedPanelLayout.horizontalPadding, x + width > maximumX {
                x = UnifiedPanelLayout.horizontalPadding
                rowY += 28 + UnifiedPanelLayout.rowSpacing
            }
            let rect = NSRect(x: x, y: rowY, width: width, height: 28)

            if index == highlightedIndex {
                NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            drawText(
                title,
                in: rect.insetBy(dx: 8, dy: 4),
                color: index == highlightedIndex ? .controlAccentColor : .labelColor,
                font: regularFont,
                lineBreakMode: .byTruncatingTail
            )
            x += width + 6
        }
    }

    private func drawTranslation(y: CGFloat) {
        guard let translationText else { return }

        drawText(
            direction.targetLabel,
            in: NSRect(x: 12, y: y + 2, width: 30, height: 18),
            color: .secondaryLabelColor,
            font: labelFont,
            lineBreakMode: .byClipping
        )

        let availableWidth = bounds.width - 58
        let height = textHeight(translationText, width: availableWidth)
        let color: NSColor = translation == .loading ? .secondaryLabelColor : .labelColor
        drawText(
            translationText,
            in: NSRect(x: 46, y: y, width: availableWidth, height: height),
            color: color,
            font: regularFont,
            lineBreakMode: .byWordWrapping
        )

        if case .result = translation {
            let targetName = direction == .chineseToEnglish ? "英文" : "中文"
            drawText(
                "⌃↩ 插入\(targetName)   ⇧⌃↩ 换行插入",
                in: NSRect(x: 46, y: y + height + 2, width: availableWidth, height: 14),
                color: .tertiaryLabelColor,
                font: shortcutFont,
                lineBreakMode: .byClipping
            )
        }
    }

    private func drawCorrection(_ correction: EnglishSpellingCorrection, y: CGFloat) {
        drawText(
            "纠错",
            in: NSRect(x: 12, y: y + 2, width: 30, height: 18),
            color: .systemOrange,
            font: labelFont,
            lineBreakMode: .byClipping
        )
        drawText(
            "\(correction.original) → \(correction.replacement)   Tab 接受",
            in: NSRect(x: 46, y: y, width: bounds.width - 58, height: 20),
            color: .labelColor,
            font: regularFont,
            lineBreakMode: .byTruncatingTail
        )
    }

    private var candidateRowWidth: CGFloat {
        let widths = candidates.enumerated().map { index, candidate in
            candidateWidth(at: index, candidate: candidate)
        }
        return widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * 6
    }

    private var candidateRowHeight: CGFloat {
        var rows = 1
        var occupiedWidth: CGFloat = 0

        for (index, candidate) in candidates.enumerated() {
            let width = min(
                candidateWidth(at: index, candidate: candidate),
                maximumCandidateContentWidth
            )
            let requiredWidth = occupiedWidth == 0 ? width : occupiedWidth + 6 + width
            if occupiedWidth > 0, requiredWidth > maximumCandidateContentWidth {
                rows += 1
                occupiedWidth = width
            } else {
                occupiedWidth = requiredWidth
            }
        }

        return CGFloat(rows) * 28 + CGFloat(max(0, rows - 1)) * UnifiedPanelLayout.rowSpacing
    }

    private var maximumCandidateContentWidth: CGFloat {
        UnifiedPanelLayout.maximumWidth - UnifiedPanelLayout.horizontalPadding * 2
    }

    private func candidateWidth(at index: Int, candidate: RimeCandidate) -> CGFloat {
        textWidth(candidateTitle(at: index, candidate: candidate), font: regularFont) + 16
    }

    private func candidateTitle(at index: Int, candidate: RimeCandidate) -> String {
        let prefix = "\(index + 1) \(candidate.text)"
        guard
            direction == .englishToChinese,
            let comment = candidate.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
            !comment.isEmpty
        else {
            return prefix
        }
        return "\(prefix) · \(comment)"
    }

    private func labeledTextWidth(label: String, value: String) -> CGFloat {
        34 + textWidth(value, font: regularFont)
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func textHeight(_ text: String, width: CGFloat) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: regularFont]
        )
        return ceil(rect.height)
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        color: NSColor,
        font: NSFont,
        lineBreakMode: NSLineBreakMode
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineBreakMode
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(string: text, attributes: attributes).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }

    private var accessibilityText: String {
        let candidateText = candidates.enumerated().map { index, candidate in
            candidateTitle(at: index, candidate: candidate)
        }.joined(separator: "，")
        let values = [
            headerContent.map { "\($0.label) \($0.value)" },
            candidateText.isEmpty ? nil : "候选 \(candidateText)",
            spellingCorrection.map { "纠错 \($0.original) 改为 \($0.replacement)" },
            translationText.map { "\(direction.targetLabel) \($0)" },
        ]
        return values.compactMap { $0 }.joined(separator: "。")
    }
}
