@preconcurrency import AppKit
@preconcurrency import Carbon
@preconcurrency import InputMethodKit

@MainActor
final class LinguaFlowApplicationDelegate: NSObject, NSApplicationDelegate {
    private var inputMethodServer: IMKServer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if InputProduct.current.usesRime {
            do {
                try AppEnvironment.shared.start()
            } catch {
                fputs("LinguaFlow startup failed: \(error.localizedDescription)\n", stderr)
            }
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

        if CommandLine.arguments.contains("--enable-input-source") {
            guard let identifier = Bundle.main.bundleIdentifier else {
                fputs("LinguaFlow bundle identifier is missing\n", stderr)
                exit(1)
            }
            let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as NSArray
            var matchingSource: TISInputSource?
            for case let candidate as TISInputSource in sources {
                guard let pointer = TISGetInputSourceProperty(candidate, kTISPropertyBundleID) else {
                    continue
                }
                let value = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue()
                if value as String == identifier {
                    matchingSource = candidate
                    break
                }
            }
            guard let matchingSource else {
                fputs("LinguaFlow input source is not registered\n", stderr)
                exit(1)
            }
            let status = TISEnableInputSource(matchingSource)
            guard status == noErr else {
                fputs("TISEnableInputSource failed with status \(status)\n", stderr)
                exit(Int32(status))
            }
            print("LinguaFlow input source enabled")
            return
        }

        let application = NSApplication.shared
        let applicationDelegate = LinguaFlowApplicationDelegate()
        application.delegate = applicationDelegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
