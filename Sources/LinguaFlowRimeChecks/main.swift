import Foundation
import LinguaFlowRime

@main
@MainActor
struct LinguaFlowRimeChecks {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fputs("usage: linguaflow-rime-checks <shared-data-dir> <user-data-dir>\n", stderr)
            exit(2)
        }

        let runtime = try RimeRuntime(
            sharedDataDirectory: URL(fileURLWithPath: CommandLine.arguments[1]),
            userDataDirectory: URL(fileURLWithPath: CommandLine.arguments[2])
        )
        let engine = try RimeEngine(runtime: runtime)
        let shiftedPunctuation: [(actual: String, unmodified: String, expected: Int32)] = [
            ("?", "/", 0x3f),
            ("~", "`", 0x7e),
            ("|", "\\", 0x7c),
        ]
        for sample in shiftedPunctuation {
            let mapped = RimeKeyboardMapper.printable(
                characters: sample.actual,
                charactersIgnoringModifiers: sample.unmodified,
                shift: true,
                control: false
            )
            guard mapped == .init(keyCode: sample.expected, modifiers: 0) else {
                fputs("Shift punctuation mapped incorrectly: \(sample), got \(String(describing: mapped))\n", stderr)
                exit(1)
            }
        }

        let question = engine.process(keyCode: 0x3f)
        guard question.commit == "？" else {
            fputs("Rime did not commit a Chinese question mark: \(question)\n", stderr)
            exit(1)
        }

        var latest = RimeSnapshot(
            consumed: false,
            preedit: "",
            candidates: [],
            highlightedIndex: 0,
            commit: nil
        )
        for scalar in "nihao".unicodeScalars {
            latest = engine.process(keyCode: Int32(scalar.value))
        }

        guard latest.consumed, !latest.preedit.isEmpty, !latest.candidates.isEmpty else {
            fputs("Rime did not produce candidates for nihao: \(latest)\n", stderr)
            exit(1)
        }

        let committed = engine.process(keyCode: 0x20)
        guard let text = committed.commit, !text.isEmpty else {
            fputs("Rime did not commit the first candidate\n", stderr)
            exit(1)
        }

        print("LinguaFlow Rime checks passed: nihao -> \(text)")
    }
}
