import Foundation

public enum TrackedTextReplacement {
    public static func hostRange(
        trackedText: String,
        trackedUTF16Range: NSRange,
        currentSelection: NSRange
    ) -> NSRange? {
        guard
            currentSelection.location != NSNotFound,
            currentSelection.length == 0,
            trackedUTF16Range.location != NSNotFound,
            NSMaxRange(trackedUTF16Range) <= trackedText.utf16.count,
            currentSelection.location >= trackedText.utf16.count
        else {
            return nil
        }

        let trackedStart = currentSelection.location - trackedText.utf16.count
        let hostLocation = trackedStart.addingReportingOverflow(trackedUTF16Range.location)
        guard !hostLocation.overflow else { return nil }

        return NSRange(
            location: hostLocation.partialValue,
            length: trackedUTF16Range.length
        )
    }
}
