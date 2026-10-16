import Foundation

public enum TrackedCaretReconciliationAction: Equatable, Sendable {
    case keepContext
    case clearContext
}

public enum TrackedCaretReconciliation {
    public static func action(
        expectedCaretLocation: Int?,
        currentSelection: NSRange,
        hasActiveComposition: Bool,
        hasTrackedContext: Bool
    ) -> TrackedCaretReconciliationAction {
        guard !hasActiveComposition, hasTrackedContext else {
            return .keepContext
        }
        guard let expectedCaretLocation else { return .clearContext }
        guard
            currentSelection.location != NSNotFound,
            currentSelection.length == 0,
            currentSelection.location == expectedCaretLocation
        else {
            return .clearContext
        }
        return .keepContext
    }
}
