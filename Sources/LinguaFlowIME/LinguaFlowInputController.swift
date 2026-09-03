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
    private let panelController = PreviewPanelController()
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
            guard let self, self.sentenceBuffer.revision == result.revision else { return }
            self.latestTranslation = result
            self.refreshPanel(translation: .result(result.translatedText))
        }
        coordinator.onError = { [weak self] error in
            self?.refreshPanel(translation: .message(error.localizedDescription))
        }
    }

    override func activateServer(_ sender: Any!) {
        activeClient = sender as? any IMKTextInput
    }

    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        clearDocumentContext()
        panelController.hide()
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

        if IsSecureEventInputEnabled(), sentenceBuffer.currentSnapshot != nil {
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
                if let updated = sentenceBuffer.removeLastCharacter() {
                    latestTranslation = nil
                    coordinator.submit(updated)
                    refreshPanel(translation: .loading)
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
            if !IsSecureEventInputEnabled(), let sentence = sentenceBuffer.append(commit) {
                latestTranslation = nil
                coordinator.submit(sentence)
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

        let translationState: PreviewPanelController.TranslationState
        if let latestTranslation {
            translationState = .result(latestTranslation.translatedText)
        } else if sentenceBuffer.currentSnapshot != nil {
            translationState = .loading
        } else {
            translationState = .hidden
        }
        panelController.update(
            candidates: currentCandidates,
            highlightedIndex: currentHighlightedIndex,
            translation: translationState
        )

        if !snapshot.candidates.isEmpty || translationState != .hidden {
            showPanel(client: client)
        } else {
            panelController.hide()
        }
    }

    private func refreshPanel(translation: PreviewPanelController.TranslationState) {
        panelController.update(
            candidates: currentCandidates,
            highlightedIndex: currentHighlightedIndex,
            translation: translation
        )
        showPanel(client: activeClient)
    }

    private func showPanel(client: (any IMKTextInput)?) {
        guard let client else { return }
        var actualRange = NSRange(location: NSNotFound, length: 0)
        let anchorRange = client.selectedRange().location == NSNotFound
            ? NSRange(location: 0, length: 0)
            : client.selectedRange()
        let anchor = client.firstRect(
            forCharacterRange: anchorRange,
            actualRange: &actualRange
        )
        panelController.show(near: anchor, clientWindowLevel: client.windowLevel())
    }

    private func clearDocumentContext() {
        engine?.clear()
        currentPreedit = ""
        currentCandidates = []
        currentHighlightedIndex = 0
        clearTranslationContext()
        panelController.hide()
    }

    private func clearTranslationContext() {
        sentenceBuffer.reset()
        latestTranslation = nil
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
