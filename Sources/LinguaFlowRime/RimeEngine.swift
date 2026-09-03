import Foundation
import LinguaFlowRimeBridge

public enum RimeKey {
    public static let backspace: Int32 = 0xff08
    public static let `return`: Int32 = 0xff0d
    public static let escape: Int32 = 0xff1b
    public static let home: Int32 = 0xff50
    public static let left: Int32 = 0xff51
    public static let up: Int32 = 0xff52
    public static let right: Int32 = 0xff53
    public static let down: Int32 = 0xff54
    public static let pageUp: Int32 = 0xff55
    public static let pageDown: Int32 = 0xff56
    public static let end: Int32 = 0xff57
}

public struct RimeCandidate: Equatable, Sendable {
    public let text: String
    public let comment: String?

    public init(text: String, comment: String?) {
        self.text = text
        self.comment = comment
    }
}

public struct RimeSnapshot: Equatable, Sendable {
    public let consumed: Bool
    public let preedit: String
    public let candidates: [RimeCandidate]
    public let highlightedIndex: Int
    public let commit: String?

    public init(
        consumed: Bool,
        preedit: String,
        candidates: [RimeCandidate],
        highlightedIndex: Int,
        commit: String?
    ) {
        self.consumed = consumed
        self.preedit = preedit
        self.candidates = candidates
        self.highlightedIndex = highlightedIndex
        self.commit = commit
    }
}

public enum RimeEngineError: Error, LocalizedError {
    case initializationFailed(String)
    case sessionCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let message), .sessionCreationFailed(let message): message
        }
    }
}

@MainActor
public final class RimeRuntime {
    private static var initialized = false

    public init(sharedDataDirectory: URL, userDataDirectory: URL, logDirectory: URL? = nil) throws {
        guard !Self.initialized else { return }
        try FileManager.default.createDirectory(
            at: userDataDirectory,
            withIntermediateDirectories: true
        )

        let success = sharedDataDirectory.path.withCString { sharedPath in
            userDataDirectory.path.withCString { userPath in
                if let logDirectory {
                    return logDirectory.path.withCString { logPath in
                        lf_rime_initialize(sharedPath, userPath, logPath)
                    }
                }
                return lf_rime_initialize(sharedPath, userPath, nil)
            }
        }

        guard success != 0 else {
            throw RimeEngineError.initializationFailed(Self.lastError)
        }
        Self.initialized = true
    }

    public static var lastError: String {
        guard let pointer = lf_rime_last_error() else { return "Unknown librime error" }
        return String(cString: pointer)
    }
}

@MainActor
public final class RimeEngine {
    nonisolated(unsafe) private var session: OpaquePointer?

    public init(runtime: RimeRuntime, schema: String = "luna_pinyin_simp") throws {
        guard let session = lf_rime_session_create() else {
            throw RimeEngineError.sessionCreationFailed(RimeRuntime.lastError)
        }
        self.session = session
        _ = schema.withCString { lf_rime_session_select_schema(session, $0) }
    }

    deinit {
        if let session {
            lf_rime_session_destroy(session)
        }
    }

    public func process(keyCode: Int32, modifiers: Int32 = 0) -> RimeSnapshot {
        guard let session else {
            return .init(consumed: false, preedit: "", candidates: [], highlightedIndex: 0, commit: nil)
        }
        let consumed = lf_rime_session_process_key(session, keyCode, modifiers) != 0
        return snapshot(consumed: consumed)
    }

    public func selectCandidate(at index: Int) -> RimeSnapshot {
        guard let session else {
            return .init(consumed: false, preedit: "", candidates: [], highlightedIndex: 0, commit: nil)
        }
        let consumed = lf_rime_session_select_candidate(session, Int32(index)) != 0
        return snapshot(consumed: consumed)
    }

    public func clear() {
        guard let session else { return }
        lf_rime_session_clear(session)
    }

    public func commitComposition() -> RimeSnapshot {
        guard let session else {
            return .init(consumed: false, preedit: "", candidates: [], highlightedIndex: 0, commit: nil)
        }
        let consumed = lf_rime_session_commit_composition(session) != 0
        return snapshot(consumed: consumed)
    }

    private func snapshot(consumed: Bool) -> RimeSnapshot {
        guard let session else {
            return .init(consumed: consumed, preedit: "", candidates: [], highlightedIndex: 0, commit: nil)
        }

        let preedit = takeString(lf_rime_session_copy_preedit(session)) ?? ""
        let commit = takeString(lf_rime_session_take_commit(session))
        let count = max(0, Int(lf_rime_session_candidate_count(session)))
        let highlightedIndex = max(0, Int(lf_rime_session_highlighted_candidate_index(session)))
        let candidates = (0..<count).compactMap { index -> RimeCandidate? in
            guard let text = takeString(lf_rime_session_copy_candidate(session, Int32(index))) else {
                return nil
            }
            let comment = takeString(lf_rime_session_copy_candidate_comment(session, Int32(index)))
            return RimeCandidate(text: text, comment: comment)
        }

        return RimeSnapshot(
            consumed: consumed,
            preedit: preedit,
            candidates: candidates,
            highlightedIndex: highlightedIndex,
            commit: commit
        )
    }

    private func takeString(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        defer { lf_rime_string_free(pointer) }
        return String(cString: pointer)
    }
}
