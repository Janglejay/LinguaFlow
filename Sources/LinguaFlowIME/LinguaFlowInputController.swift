@preconcurrency import AppKit
@preconcurrency import Carbon
@preconcurrency import InputMethodKit
import LinguaFlowCore
import LinguaFlowRime

@objc(LinguaFlowInputController)
@MainActor
final class LinguaFlowInputController: IMKInputController {
    private let product = InputProduct.current
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
    private var spellingCorrection: EnglishSpellingCorrection?
    private var spellCheckRevision: UInt64 = 0
    private var spellCheckTask: Task<Void, Never>?
    private var expectedEnglishCaretLocation: Int?
    private let englishSpellChecker = EnglishSpellChecker()
    private var englishCandidateContext: EnglishCandidateContext?
    private var candidateMeaningRevision: UInt64 = 0
    private var candidateMeaningTask: Task<Void, Never>?
    private var candidateMeaningCache: [String: String] = [:]
    private var candidateTranslationProvider: OnDeviceTranslationProvider?
    private var lastValidAnchor: NSRect?
    private let panelController = PreviewPanelController.shared
    private var coordinator: TranslationCoordinator!

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        activeClient = inputClient as? any IMKTextInput
        if product.usesRime {
            engine = try? AppEnvironment.shared.makeEngine()
        }

        let sentenceTranslationProvider = OnDeviceTranslationProvider(
            direction: product.translationDirection
        )
        coordinator = TranslationCoordinator(
            provider: sentenceTranslationProvider,
            debounce: .milliseconds(400)
        )
        if product == .english {
            candidateTranslationProvider = OnDeviceTranslationProvider(
                direction: .englishToChinese
            )
        }
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
        guard let event, event.type == .keyDown else { return false }
        let client = client(from: sender)
        activeClient = client
        captureCaretAnchor(client: client)

        if IsSecureEventInputEnabled() {
            clearDocumentContext()
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.option) {
            if product == .english {
                clearDocumentContext()
            }
            return false
        }

        if product == .english {
            reconcileEnglishCaret(client: client)
        }

        if isReturn(event), modifiers.contains(.control), let translation = latestTranslation {
            let prefix = modifiers.contains(.shift) ? "\n" : " "
            client?.insertText(
                prefix + translation.translatedText,
                replacementRange: Self.notFoundRange
            )
            if product == .english {
                clearDocumentContext()
            }
            return true
        }

        if product == .english {
            return handleEnglish(event, client: client, modifiers: modifiers)
        }

        guard let engine else { return false }
        guard let key = rimeKeyMapping(for: event, modifiers: modifiers) else { return false }
        let snapshot = engine.process(keyCode: key.keyCode, modifiers: key.modifiers)
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

    private func updateTranslationDraftAndPanel(
        client: (any IMKTextInput)?,
        refreshEnglishCandidates: Bool = true
    ) {
        let provisionalCandidate: String?
        if !currentPreedit.isEmpty, currentCandidates.indices.contains(currentHighlightedIndex) {
            provisionalCandidate = currentCandidates[currentHighlightedIndex].text
        } else {
            provisionalCandidate = nil
        }

        let sourceText: String?
        switch product {
        case .chinese:
            sourceText = LiveTranslationDraft.sourceText(
                committed: sentenceBuffer.currentSnapshot,
                provisionalCandidate: provisionalCandidate
            )
        case .english:
            sourceText = sentenceBuffer.currentSnapshot?.text
        }

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

        if product == .english {
            if refreshEnglishCandidates {
                updateEnglishCandidates(for: sourceText)
            }
            scheduleSpellingCheck(for: sourceText)
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
            translation: translationState,
            direction: product.translationDirection,
            spellingCorrection: spellingCorrection
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

        var lineHeightRect = NSRect.zero
        _ = client.attributes(
            forCharacterIndex: 0,
            lineHeightRectangle: &lineHeightRect
        )

        let markedRange = client.markedRange()
        let selectedRange = client.selectedRange()
        let preferredRanges = currentPreedit.isEmpty
            ? [selectedRange, markedRange]
            : [markedRange, selectedRange]
        var candidates = [lineHeightRect]
        for range in preferredRanges where range.location != NSNotFound {
            let endLocation = range.location.addingReportingOverflow(range.length)
            guard !endLocation.overflow else { continue }

            var actualRange = NSRange(location: NSNotFound, length: 0)
            let rect = client.firstRect(
                forCharacterRange: NSRange(location: endLocation.partialValue, length: 0),
                actualRange: &actualRange
            )
            candidates.append(rect)
        }

        if let anchor = UnifiedPanelLayout.firstUsableAnchor(
            candidates: candidates,
            visibleFrames: NSScreen.screens.map(\.frame)
        ) {
            lastValidAnchor = anchor
        }
    }

    private func clearDocumentContext() {
        engine?.clear()
        currentPreedit = ""
        currentCandidates = []
        currentHighlightedIndex = 0
        clearEnglishCandidates()
        candidateMeaningCache.removeAll(keepingCapacity: true)
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
        spellingCorrection = nil
        expectedEnglishCaretLocation = nil
        spellCheckRevision &+= 1
        spellCheckTask?.cancel()
        spellCheckTask = nil
        coordinator.cancel()
    }

    private func handleEnglish(
        _ event: NSEvent,
        client: (any IMKTextInput)?,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        switch EnglishCandidateInteraction.action(
            keyCode: event.keyCode,
            characters: event.characters,
            candidateCount: currentCandidates.count,
            highlightedIndex: currentHighlightedIndex,
            hasShift: modifiers.contains(.shift),
            hasControl: modifiers.contains(.control)
        ) {
        case .passThrough:
            break
        case .dismiss:
            clearEnglishCandidates()
            renderPanel(client: client)
            return true
        case .select(let index):
            if applyEnglishCandidate(at: index, client: client) {
                return true
            }
            clearDocumentContext()
            return false
        case .highlight(let index):
            currentHighlightedIndex = index
            renderPanel(client: client)
            return true
        }

        if event.keyCode == 48, applySpellingCorrection(client: client) {
            return true
        }
        if event.keyCode == 48 {
            clearDocumentContext()
            return false
        }

        if event.keyCode == 51 {
            let selection = client?.selectedRange()
            if sentenceBuffer.removeLastCharacter() != nil {
                updateTranslationDraftAndPanel(client: client)
            } else {
                clearDocumentContext()
            }
            if let selection, selection.location != NSNotFound, selection.location > 0 {
                expectedEnglishCaretLocation = selection.location - 1
            }
            return false
        }

        if isNavigationKey(event.keyCode) || event.keyCode == 53 {
            clearDocumentContext()
            return false
        }

        if isReturn(event) {
            let selection = client?.selectedRange()
            if sentenceBuffer.append("\n") != nil {
                updateTranslationDraftAndPanel(client: client)
            }
            if let selection, selection.location != NSNotFound {
                expectedEnglishCaretLocation = selection.location + 1
            }
            return false
        }

        guard !modifiers.contains(.control), let characters = event.characters else {
            return false
        }
        guard
            !characters.isEmpty,
            characters.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
            })
        else {
            return false
        }

        let selection = client?.selectedRange()
        if sentenceBuffer.append(characters) != nil {
            updateTranslationDraftAndPanel(client: client)
        }
        if let selection, selection.location != NSNotFound {
            expectedEnglishCaretLocation = selection.location + characters.utf16.count
        }
        return false
    }

    private func updateEnglishCandidates(for sourceText: String?) {
        guard
            let sourceText,
            let context = EnglishCandidateContext.trailingWord(in: sourceText)
        else {
            clearEnglishCandidates()
            return
        }

        let words = englishSpellChecker.candidates(for: context.word)
        guard !words.isEmpty else {
            clearEnglishCandidates()
            return
        }

        if englishCandidateContext == context, currentCandidates.map(\.text) == words {
            return
        }

        englishCandidateContext = context
        currentHighlightedIndex = 0
        currentCandidates = words.map { word in
            RimeCandidate(
                text: word,
                comment: candidateMeaningCache[word.lowercased()]
            )
        }
        scheduleCandidateMeanings(for: words)
    }

    private func scheduleCandidateMeanings(for words: [String]) {
        candidateMeaningRevision &+= 1
        let revision = candidateMeaningRevision
        candidateMeaningTask?.cancel()

        let missingWords = words.filter { candidateMeaningCache[$0.lowercased()] == nil }
        guard !missingWords.isEmpty, let provider = candidateTranslationProvider else {
            return
        }

        candidateMeaningTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                let meanings = try await provider.translateCandidates(missingWords)
                try Task.checkCancellation()
                guard
                    let self,
                    self.candidateMeaningRevision == revision,
                    self.currentCandidates.map(\.text) == words
                else {
                    return
                }

                for (word, meaning) in meanings {
                    self.candidateMeaningCache[word] = self.compactCandidateMeaning(meaning)
                }
                self.currentCandidates = words.map { word in
                    RimeCandidate(
                        text: word,
                        comment: self.candidateMeaningCache[word.lowercased()]
                    )
                }
                self.renderPanel(client: self.activeClient)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func applyEnglishCandidate(
        at index: Int,
        client: (any IMKTextInput)?
    ) -> Bool {
        guard
            let client,
            currentCandidates.indices.contains(index),
            let context = englishCandidateContext,
            let snapshot = sentenceBuffer.currentSnapshot,
            let hostRange = TrackedTextReplacement.hostRange(
                trackedText: snapshot.text,
                trackedUTF16Range: context.range,
                currentSelection: client.selectedRange()
            ),
            client.attributedSubstring(from: hostRange)?.string == context.word
        else {
            return false
        }

        let replacement = currentCandidates[index].text
        client.insertText(replacement, replacementRange: hostRange)
        expectedEnglishCaretLocation = hostRange.location + replacement.utf16.count
        _ = sentenceBuffer.replaceCharacters(inUTF16Range: context.range, with: replacement)
        spellingCorrection = nil
        clearEnglishCandidates()
        updateTranslationDraftAndPanel(
            client: client,
            refreshEnglishCandidates: false
        )
        return true
    }

    private func clearEnglishCandidates() {
        englishCandidateContext = nil
        if product == .english {
            currentCandidates = []
        }
        currentHighlightedIndex = 0
        candidateMeaningRevision &+= 1
        candidateMeaningTask?.cancel()
        candidateMeaningTask = nil
    }

    private func compactCandidateMeaning(_ meaning: String) -> String {
        let compact = meaning
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > 16 else { return compact }
        return String(compact.prefix(16)) + "…"
    }

    private func reconcileEnglishCaret(client: (any IMKTextInput)?) {
        guard let expectedEnglishCaretLocation else { return }
        let selection = client?.selectedRange() ?? Self.notFoundRange
        guard selection.location == expectedEnglishCaretLocation, selection.length == 0 else {
            clearDocumentContext()
            return
        }
    }

    private func scheduleSpellingCheck(for sourceText: String?) {
        spellCheckRevision &+= 1
        let revision = spellCheckRevision
        spellCheckTask?.cancel()

        guard let sourceText, sourceText.rangeOfCharacter(from: .letters) != nil else {
            spellingCorrection = nil
            return
        }

        spellCheckTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
                guard let self, self.spellCheckRevision == revision else { return }
                self.spellingCorrection = self.englishSpellChecker.firstCorrection(in: sourceText)
                self.renderPanel(client: self.activeClient)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func applySpellingCorrection(client: (any IMKTextInput)?) -> Bool {
        guard
            let client,
            let correction = spellingCorrection,
            let snapshot = sentenceBuffer.currentSnapshot
        else {
            return false
        }

        let textLength = snapshot.text.utf16.count
        let correctionEnd = NSMaxRange(correction.range)
        guard correctionEnd <= textLength else { return false }

        let suffixRange = NSRange(
            location: correction.range.location,
            length: textLength - correction.range.location
        )
        guard
            let suffixStringRange = Range(suffixRange, in: snapshot.text),
            let correctionStringRange = Range(correction.range, in: snapshot.text),
            let hostRange = TrackedTextReplacement.hostRange(
                trackedText: snapshot.text,
                trackedUTF16Range: suffixRange,
                currentSelection: client.selectedRange()
            )
        else {
            return false
        }

        let suffix = snapshot.text[suffixStringRange]
        let original = snapshot.text[correctionStringRange]
        guard suffix.hasPrefix(original) else { return false }
        guard client.attributedSubstring(from: hostRange)?.string == String(suffix) else {
            clearDocumentContext()
            return false
        }
        let trailingText = suffix.dropFirst(original.count)
        let replacement = correction.replacement + trailingText

        client.insertText(replacement, replacementRange: hostRange)
        expectedEnglishCaretLocation = hostRange.location + replacement.utf16.count
        _ = sentenceBuffer.replaceCharacters(inUTF16Range: suffixRange, with: replacement)
        spellingCorrection = nil
        updateTranslationDraftAndPanel(client: client)
        return true
    }

    private func client(from sender: Any?) -> (any IMKTextInput)? {
        (sender as? any IMKTextInput) ?? activeClient
    }

    private func rimeKeyMapping(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> RimeKeyMapping? {
        let specialKey: Int32?
        switch event.keyCode {
        case 36, 76: specialKey = RimeKey.return
        case 51: specialKey = RimeKey.backspace
        case 53: specialKey = RimeKey.escape
        case 115: specialKey = RimeKey.home
        case 116: specialKey = RimeKey.pageUp
        case 119: specialKey = RimeKey.end
        case 121: specialKey = RimeKey.pageDown
        case 123: specialKey = RimeKey.left
        case 124: specialKey = RimeKey.right
        case 125: specialKey = RimeKey.down
        case 126: specialKey = RimeKey.up
        default:
            specialKey = nil
        }

        if let specialKey {
            return RimeKeyMapping(
                keyCode: specialKey,
                modifiers: rimeModifiers(from: modifiers)
            )
        }

        return RimeKeyboardMapper.printable(
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            shift: modifiers.contains(.shift),
            control: modifiers.contains(.control)
        )
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
