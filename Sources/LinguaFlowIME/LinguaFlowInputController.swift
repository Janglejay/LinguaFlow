@preconcurrency import AppKit
@preconcurrency import Carbon
@preconcurrency import InputMethodKit
import LinguaFlowCore
import LinguaFlowRime

@objc(LinguaFlowInputController)
@MainActor
final class LinguaFlowInputController: IMKInputController {
    private var activeClient: (any IMKTextInput)?
    private var engine: RimeEngine?
    private var currentPreedit = ""
    private var currentCandidates: [RimeCandidate] = []
    private var currentHighlightedIndex = 0
    private var sentenceBuffer = CommittedSentenceBuffer(maxCharacters: 280)
    private var latestTranslation: TranslationResult?
    private var translationRevision: UInt64 = 0
    private var translationSourceText: String?
    private var translationState: PreviewPanelController.TranslationState = .hidden
    private var lastValidAnchor: NSRect?
    private let panelController = PreviewPanelController.shared
    private var coordinator: TranslationCoordinator!

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        activeClient = inputClient as? any IMKTextInput
        engine = try? AppEnvironment.shared.makeEngine()

        coordinator = TranslationCoordinator(
            provider: OnDeviceTranslationProvider(),
            debounce: .milliseconds(400)
        )
        coordinator.onResult = { [weak self] result in
            guard
                let self,
                self.translationRevision == result.revision,
                self.translationSourceText == result.sourceText
            else {
                return
            }
            self.latestTranslation = result
            self.translationState = .result(result.translatedText)
            self.renderPanel(client: self.activeClient)
        }
        coordinator.onError = { [weak self] error in
            guard let self else { return }
            self.translationState = .message(error.localizedDescription)
            self.renderPanel(client: self.activeClient)
        }
    }

    override func activateServer(_ sender: Any!) {
        activeClient = sender as? any IMKTextInput
    }

    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        clearDocumentContext()
        panelController.hide(owner: self)
        lastValidAnchor = nil
        activeClient = nil
    }

    override func commitComposition(_ sender: Any!) {
        guard !currentPreedit.isEmpty, let engine else { return }
        let snapshot = engine.commitComposition()
        apply(snapshot, client: client(from: sender))
    }

    override func composedString(_ sender: Any!) -> Any! {
        currentPreedit
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        []
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "LinguaFlow")
        let setupItem = NSMenuItem(
            title: "准备本地中英翻译…",
            action: #selector(openTranslationSetup),
            keyEquivalent: ""
        )
        setupItem.target = self
        menu.addItem(setupItem)
        return menu
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let engine else { return false }
        let client = client(from: sender)
        activeClient = client
        captureCaretAnchor(client: client)

        if IsSecureEventInputEnabled(), translationSourceText != nil {
            clearTranslationContext()
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.option) {
            return false
        }

        if isReturn(event), modifiers.contains(.control), let translation = latestTranslation {
            let prefix = modifiers.contains(.shift) ? "\n" : " "
            client?.insertText(
                prefix + translation.translatedText,
                replacementRange: Self.notFoundRange
            )
            return true
        }

        guard let keyCode = rimeKeyCode(for: event) else { return false }
        let snapshot = engine.process(keyCode: keyCode, modifiers: rimeModifiers(from: modifiers))
        apply(snapshot, client: client)

        if !snapshot.consumed {
            if event.keyCode == 51 {
                if sentenceBuffer.removeLastCharacter() != nil {
                    updateTranslationDraftAndPanel(client: client)
                } else {
                    clearDocumentContext()
                }
            } else if isNavigationKey(event.keyCode) {
                clearDocumentContext()
            }
        }

        return snapshot.consumed
    }

    private func apply(_ snapshot: RimeSnapshot, client: (any IMKTextInput)?) {
        if let commit = snapshot.commit, !commit.isEmpty {
            client?.insertText(commit, replacementRange: Self.notFoundRange)
            if !IsSecureEventInputEnabled() {
                sentenceBuffer.append(commit)
            }
        }

        if snapshot.preedit != currentPreedit {
            currentPreedit = snapshot.preedit
            client?.setMarkedText(
                snapshot.preedit,
                selectionRange: NSRange(location: snapshot.preedit.utf16.count, length: 0),
                replacementRange: Self.notFoundRange
            )
        }

        currentCandidates = snapshot.candidates
        currentHighlightedIndex = snapshot.highlightedIndex
        updateTranslationDraftAndPanel(client: client)
    }

    private func updateTranslationDraftAndPanel(client: (any IMKTextInput)?) {
        let provisionalCandidate: String?
        if !currentPreedit.isEmpty, currentCandidates.indices.contains(currentHighlightedIndex) {
            provisionalCandidate = currentCandidates[currentHighlightedIndex].text
        } else {
            provisionalCandidate = nil
        }

        let sourceText = LiveTranslationDraft.sourceText(
            committed: sentenceBuffer.currentSnapshot,
            provisionalCandidate: provisionalCandidate
        )

        if sourceText != translationSourceText {
            translationSourceText = sourceText
            latestTranslation = nil

            if let sourceText {
                translationRevision &+= 1
                translationState = .loading
                coordinator.submit(
                    SentenceSnapshot(
                        text: sourceText,
                        revision: translationRevision,
                        isFinal: false
                    )
                )
            } else {
                translationState = .hidden
                coordinator.cancel()
            }
        }

        renderPanel(client: client)
    }

    private func renderPanel(client: (any IMKTextInput)?) {
        panelController.update(
            owner: self,
            preedit: currentPreedit,
            sourceText: translationSourceText,
            candidates: currentCandidates,
            highlightedIndex: currentHighlightedIndex,
            translation: translationState
        )

        if !currentPreedit.isEmpty || !currentCandidates.isEmpty || translationState != .hidden {
            showPanel(client: client)
        } else {
            panelController.hide(owner: self)
        }
    }

    private func showPanel(client: (any IMKTextInput)?) {
        guard let client else { return }
        guard let lastValidAnchor else {
            panelController.hide(owner: self)
            return
        }
        panelController.show(
            owner: self,
            near: lastValidAnchor,
            clientWindowLevel: client.windowLevel()
        )
    }

    private func captureCaretAnchor(client: (any IMKTextInput)?) {
        guard let client else { return }

        let markedRange = client.markedRange()
        let selectedRange = client.selectedRange()
        let preferredRanges = currentPreedit.isEmpty
            ? [selectedRange, markedRange]
            : [markedRange, selectedRange]
        for range in preferredRanges where range.location != NSNotFound {
            let endLocation = range.location.addingReportingOverflow(range.length)
            guard !endLocation.overflow else { continue }

            var actualRange = NSRange(location: NSNotFound, length: 0)
            let rect = client.firstRect(
                forCharacterRange: NSRange(location: endLocation.partialValue, length: 0),
                actualRange: &actualRange
            )
            guard isUsableAnchor(rect) else { continue }
            lastValidAnchor = rect
            return
        }
    }

    private func isUsableAnchor(_ rect: NSRect) -> Bool {
        guard
            rect.origin.x.isFinite,
            rect.origin.y.isFinite,
            rect.size.width.isFinite,
            rect.size.height.isFinite,
            rect.size.height > 0
        else {
            return false
        }

        let point = rect.origin
        return NSScreen.screens.contains { screen in
            screen.frame.insetBy(dx: -1, dy: -1).contains(point)
        }
    }

    private func clearDocumentContext() {
        engine?.clear()
        currentPreedit = ""
        currentCandidates = []
        currentHighlightedIndex = 0
        clearTranslationContext()
        panelController.hide(owner: self)
        lastValidAnchor = nil
    }

    private func clearTranslationContext() {
        sentenceBuffer.reset()
        latestTranslation = nil
        translationRevision &+= 1
        translationSourceText = nil
        translationState = .hidden
        coordinator.cancel()
    }

    private func client(from sender: Any?) -> (any IMKTextInput)? {
        (sender as? any IMKTextInput) ?? activeClient
    }

    private func rimeKeyCode(for event: NSEvent) -> Int32? {
        switch event.keyCode {
        case 36, 76: return RimeKey.return
        case 51: return RimeKey.backspace
        case 53: return RimeKey.escape
        case 115: return RimeKey.home
        case 116: return RimeKey.pageUp
        case 119: return RimeKey.end
        case 121: return RimeKey.pageDown
        case 123: return RimeKey.left
        case 124: return RimeKey.right
        case 125: return RimeKey.down
        case 126: return RimeKey.up
        default:
            guard
                let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
                scalar.isASCII
            else {
                return nil
            }
            return Int32(scalar.value)
        }
    }

    private func rimeModifiers(from modifiers: NSEvent.ModifierFlags) -> Int32 {
        var result: Int32 = 0
        if modifiers.contains(.shift) { result |= 1 }
        if modifiers.contains(.control) { result |= 4 }
        return result
    }

    private func isReturn(_ event: NSEvent) -> Bool {
        event.keyCode == 36 || event.keyCode == 76
    }

    private func isNavigationKey(_ keyCode: UInt16) -> Bool {
        [115, 116, 119, 121, 123, 124, 125, 126].contains(keyCode)
    }

    @objc
    private func openTranslationSetup() {
        let setupURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("LinguaFlowSetup.app", isDirectory: true)
        NSWorkspace.shared.open(setupURL)
    }

    private static let notFoundRange = NSRange(location: NSNotFound, length: NSNotFound)
}
