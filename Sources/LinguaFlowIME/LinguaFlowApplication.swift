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
    private static func stringProperty(
        _ source: TISInputSource,
        key: CFString
    ) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func boolProperty(
        _ source: TISInputSource,
        key: CFString
    ) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return false
        }
        return CFBooleanGetValue(
            Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        )
    }

    private static func inputSource(
        bundleIdentifier: String,
        sourceIdentifier: String,
        includeAllInstalled: Bool
    ) -> TISInputSource? {
        let sources = TISCreateInputSourceList(nil, includeAllInstalled)
            .takeRetainedValue() as NSArray
        for case let candidate as TISInputSource in sources {
            guard stringProperty(candidate, key: kTISPropertyBundleID) == bundleIdentifier,
                  stringProperty(candidate, key: kTISPropertyInputSourceID) == sourceIdentifier else {
                continue
            }
            return candidate
        }
        return nil
    }

    private static func inputSourceIdentifiers() -> (bundle: String, source: String)? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let sourceIdentifier = Bundle.main.object(
                forInfoDictionaryKey: "TISInputSourceID"
              ) as? String,
              !sourceIdentifier.isEmpty else {
            return nil
        }
        return (bundleIdentifier, sourceIdentifier)
    }

    private static func hasSupportedInstallationPath(bundleIdentifier: String) -> Bool {
        let bundleName: String
        switch bundleIdentifier {
        case "com.fufangjie.inputmethod.LinguaFlow":
            bundleName = "LinguaFlow.app"
        case "com.fufangjie.inputmethod.LinguaFlowEnglish":
            bundleName = "LinguaFlowEnglish.app"
        default:
            return false
        }

        let currentPath = Bundle.main.bundleURL.standardizedFileURL.path
        let systemPath = "/Library/Input Methods/\(bundleName)"
        let userPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods", isDirectory: true)
            .appendingPathComponent(bundleName, isDirectory: true)
            .standardizedFileURL.path
        return currentPath == systemPath || currentPath == userPath
    }

    private static func isEnabledAndSelectable(
        bundleIdentifier: String,
        sourceIdentifier: String
    ) -> Bool {
        guard hasSupportedInstallationPath(bundleIdentifier: bundleIdentifier),
              let source = inputSource(
                bundleIdentifier: bundleIdentifier,
                sourceIdentifier: sourceIdentifier,
                includeAllInstalled: false
              ) else {
            return false
        }
        return boolProperty(source, key: kTISPropertyInputSourceIsEnabled)
            && boolProperty(source, key: kTISPropertyInputSourceIsSelectCapable)
    }

    private static func installInputSource(
        bundleIdentifier: String,
        sourceIdentifier: String
    ) -> Bool {
        guard hasSupportedInstallationPath(bundleIdentifier: bundleIdentifier) else {
            fputs("LinguaFlow is not running from a supported Input Methods path\n", stderr)
            return false
        }
        let registerStatus = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
        guard registerStatus == noErr else {
            fputs("TISRegisterInputSource failed with status \(registerStatus)\n", stderr)
            return false
        }

        // LaunchServices may publish a newly installed input method slightly
        // after TISRegisterInputSource returns. Poll a fresh list instead of
        // treating a noErr registration result as proof that the source exists.
        for _ in 0..<15 {
            if hasSupportedInstallationPath(bundleIdentifier: bundleIdentifier),
               let source = inputSource(
                bundleIdentifier: bundleIdentifier,
                sourceIdentifier: sourceIdentifier,
                includeAllInstalled: true
               ) {
                let enableStatus = TISEnableInputSource(source)
                if enableStatus == noErr {
                    var stableChecks = 0
                    for _ in 0..<2 {
                        Thread.sleep(forTimeInterval: 0.2)
                        if isEnabledAndSelectable(
                            bundleIdentifier: bundleIdentifier,
                            sourceIdentifier: sourceIdentifier
                        ) {
                            stableChecks += 1
                        } else {
                            break
                        }
                    }
                    if stableChecks == 2 {
                        print("LinguaFlow input source registered, enabled, and verified")
                        return true
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        fputs("LinguaFlow input source did not become enabled and selectable\n", stderr)
        return false
    }

    static func main() {
        if CommandLine.arguments.contains("--install-input-source") {
            guard let identifiers = inputSourceIdentifiers() else {
                fputs("LinguaFlow input-source identifiers are missing\n", stderr)
                exit(1)
            }
            exit(installInputSource(
                bundleIdentifier: identifiers.bundle,
                sourceIdentifier: identifiers.source
            ) ? 0 : 1)
        }

        if CommandLine.arguments.contains("--verify-input-source") {
            guard let identifiers = inputSourceIdentifiers() else {
                fputs("LinguaFlow input-source identifiers are missing\n", stderr)
                exit(1)
            }
            guard isEnabledAndSelectable(
                bundleIdentifier: identifiers.bundle,
                sourceIdentifier: identifiers.source
            ) else {
                fputs("LinguaFlow input source is not enabled and selectable\n", stderr)
                exit(1)
            }
            print("LinguaFlow input source is enabled and selectable")
            return
        }

        if CommandLine.arguments.contains("--register-input-source") {
            guard let identifiers = inputSourceIdentifiers(),
                  hasSupportedInstallationPath(bundleIdentifier: identifiers.bundle) else {
                fputs("LinguaFlow is not running from a supported Input Methods path\n", stderr)
                exit(1)
            }
            let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
            if status != noErr {
                fputs("TISRegisterInputSource failed with status \(status)\n", stderr)
                exit(Int32(status))
            }
            print("LinguaFlow input source registered")
            return
        }

        if CommandLine.arguments.contains("--enable-input-source") {
            guard let identifiers = inputSourceIdentifiers() else {
                fputs("LinguaFlow input-source identifiers are missing\n", stderr)
                exit(1)
            }
            guard hasSupportedInstallationPath(bundleIdentifier: identifiers.bundle) else {
                fputs("LinguaFlow is not running from a supported Input Methods path\n", stderr)
                exit(1)
            }
            let matchingSource = inputSource(
                bundleIdentifier: identifiers.bundle,
                sourceIdentifier: identifiers.source,
                includeAllInstalled: true
            )
            guard let matchingSource else {
                fputs("LinguaFlow input source is not registered\n", stderr)
                exit(1)
            }
            let status = TISEnableInputSource(matchingSource)
            guard status == noErr else {
                fputs("TISEnableInputSource failed with status \(status)\n", stderr)
                exit(Int32(status))
            }
            guard isEnabledAndSelectable(
                bundleIdentifier: identifiers.bundle,
                sourceIdentifier: identifiers.source
            ) else {
                fputs("LinguaFlow input source did not become enabled and selectable\n", stderr)
                exit(1)
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
