import AppKit
import LinguaFlowRime

@MainActor
final class PreviewPanelController {
    enum TranslationState: Equatable {
        case hidden
        case loading
        case result(String)
        case message(String)
    }

    private let panel: NSPanel
    private let previewView: PreviewView

    init() {
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
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func update(
        candidates: [RimeCandidate],
        highlightedIndex: Int,
        translation: TranslationState
    ) {
        previewView.update(
            candidates: Array(candidates.prefix(5)),
            highlightedIndex: highlightedIndex,
            translation: translation
        )
        panel.setContentSize(previewView.preferredSize)
    }

    func show(near anchor: NSRect, clientWindowLevel: CGWindowLevel?) {
        if let clientWindowLevel {
            panel.level = NSWindow.Level(rawValue: Int(clientWindowLevel) + 1)
        }

        let visibleFrame = NSScreen.screens
            .first(where: { $0.frame.intersects(anchor) })?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = previewView.preferredSize
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - 6)

        if origin.y < visibleFrame.minY {
            origin.y = anchor.maxY + 6
        }
        origin.x = min(max(origin.x, visibleFrame.minX + 6), visibleFrame.maxX - size.width - 6)
        origin.y = min(max(origin.y, visibleFrame.minY + 6), visibleFrame.maxY - size.height - 6)

        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

@MainActor
private final class PreviewView: NSView {
    private(set) var preferredSize = NSSize(width: 360, height: 64)
    private var candidates: [RimeCandidate] = []
    private var highlightedIndex = 0
    private var translation: PreviewPanelController.TranslationState = .hidden

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("LinguaFlow 候选与英文预览")
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        candidates: [RimeCandidate],
        highlightedIndex: Int,
        translation: PreviewPanelController.TranslationState
    ) {
        self.candidates = candidates
        self.highlightedIndex = highlightedIndex
        self.translation = translation
        preferredSize = calculateSize()
        frame.size = preferredSize
        needsDisplay = true
        setAccessibilityValue(accessibilityText)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor.windowBackgroundColor.withAlphaComponent(0.97).setFill()
        background.fill()

        var y: CGFloat = 12
        if !candidates.isEmpty {
            for (index, candidate) in candidates.enumerated() {
                let label = "\(index + 1)  \(candidate.text)"
                drawText(
                    label,
                    at: NSPoint(x: 14, y: y),
                    color: index == highlightedIndex ? .controlAccentColor : .labelColor
                )
                y += 24
            }
        }

        if translation != .hidden {
            if !candidates.isEmpty {
                NSColor.separatorColor.setStroke()
                let divider = NSBezierPath()
                divider.move(to: NSPoint(x: 12, y: y + 2))
                divider.line(to: NSPoint(x: bounds.width - 12, y: y + 2))
                divider.stroke()
                y += 12
            }

            let text: String
            let color: NSColor
            switch translation {
            case .hidden:
                return
            case .loading:
                text = "正在生成本地英文预览…"
                color = .secondaryLabelColor
            case .result(let value):
                text = value
                color = .labelColor
            case .message(let value):
                text = value
                color = .secondaryLabelColor
            }
            drawText(text, at: NSPoint(x: 14, y: y), color: color, maxWidth: bounds.width - 28)

            if case .result = translation {
                drawText(
                    "⌃↩ 插入英文   ⇧⌃↩ 换行插入",
                    at: NSPoint(x: 14, y: bounds.height - 24),
                    color: .tertiaryLabelColor,
                    fontSize: 11
                )
            }
        }
    }

    private func calculateSize() -> NSSize {
        var height: CGFloat = 24
        height += CGFloat(candidates.count) * 24
        if translation != .hidden {
            if !candidates.isEmpty { height += 12 }
            switch translation {
            case .result(let text):
                height += textHeight(text, width: 500) + 28
            case .loading, .message:
                height += 34
            case .hidden:
                break
            }
        }
        return NSSize(width: 528, height: max(48, height))
    }

    private func textHeight(_ text: String, width: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14)]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return ceil(rect.height)
    }

    private func drawText(
        _ text: String,
        at point: NSPoint,
        color: NSColor,
        fontSize: CGFloat = 14,
        maxWidth: CGFloat? = nil
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let value = NSAttributedString(string: text, attributes: attributes)
        if let maxWidth {
            value.draw(
                with: NSRect(x: point.x, y: point.y, width: maxWidth, height: bounds.height - point.y),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        } else {
            value.draw(at: point)
        }
    }

    private var accessibilityText: String {
        let candidateText = candidates.map(\.text).joined(separator: "，")
        let translationText: String
        switch translation {
        case .hidden: translationText = ""
        case .loading: translationText = "正在翻译"
        case .result(let value), .message(let value): translationText = value
        }
        return [candidateText, translationText].filter { !$0.isEmpty }.joined(separator: "。")
    }
}
