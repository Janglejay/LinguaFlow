@preconcurrency import AppKit
@preconcurrency import Carbon
@preconcurrency import InputMethodKit

@MainActor
final class LinguaFlowApplicationDelegate: NSObject, NSApplicationDelegate {
    private var inputMethodServer: IMKServer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        do {
            try AppEnvironment.shared.start()
        } catch {
            fputs("LinguaFlow startup failed: \(error.localizedDescription)\n", stderr)
        }

        let bundle = Bundle.main
        let identifier = bundle.bundleIdentifier ?? "com.fufangjie.inputmethod.LinguaFlow"
        let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
            ?? "com.fufangjie.inputmethod.LinguaFlow_Connection"
        inputMethodServer = IMKServer(name: connectionName, bundleIdentifier: identifier)
    }
}

@main
@MainActor
enum LinguaFlowApplication {
    static func main() {
        if CommandLine.arguments.contains("--register-input-source") {
            let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
            if status != noErr {
                fputs("TISRegisterInputSource failed with status \(status)\n", stderr)
                exit(Int32(status))
            }
            print("LinguaFlow input source registered")
            return
        }

        let application = NSApplication.shared
        let applicationDelegate = LinguaFlowApplicationDelegate()
        application.delegate = applicationDelegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
