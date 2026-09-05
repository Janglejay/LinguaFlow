#!/usr/bin/env swift

import AppKit
import Carbon
import Foundation

struct ExpectedInputSource {
    let identifier: String
    let path: String
    let executable: String
    let sourceInfoPlist: String
}

let expectedSources = [
    ExpectedInputSource(
        identifier: "com.fufangjie.inputmethod.LinguaFlow",
        path: "/Library/Input Methods/LinguaFlow.app",
        executable: "LinguaFlowIME",
        sourceInfoPlist: "Resources/Info.plist"
    ),
    ExpectedInputSource(
        identifier: "com.fufangjie.inputmethod.LinguaFlowEnglish",
        path: "/Library/Input Methods/LinguaFlowEnglish.app",
        executable: "LinguaFlowEnglishIME",
        sourceInfoPlist: "Resources/English-Info.plist"
    ),
]

func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else {
        return nil
    }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

func boolProperty(_ source: TISInputSource, key: CFString) -> Bool {
    guard let pointer = TISGetInputSourceProperty(source, key) else {
        return false
    }
    return CFBooleanGetValue(
        Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
    )
}

let enabledSources = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
var failures: [String] = []

for expected in expectedSources {
    let expectedInfoURL = repositoryRoot.appendingPathComponent(expected.sourceInfoPlist)
    guard let expectedInfo = NSDictionary(contentsOf: expectedInfoURL),
          let expectedShortVersion = expectedInfo["CFBundleShortVersionString"] as? String,
          let expectedBundleVersion = expectedInfo["CFBundleVersion"] as? String else {
        failures.append("\(expected.identifier): could not read source version metadata")
        continue
    }

    var isDirectory = ObjCBool(false)
    if !FileManager.default.fileExists(atPath: expected.path, isDirectory: &isDirectory)
        || !isDirectory.boolValue {
        failures.append("\(expected.identifier): system bundle is missing at \(expected.path)")
        continue
    }
    guard let bundle = Bundle(url: URL(fileURLWithPath: expected.path)),
          bundle.bundleIdentifier == expected.identifier,
          bundle.object(forInfoDictionaryKey: "TISInputSourceID") as? String
            == expected.identifier else {
        failures.append("\(expected.identifier): system bundle metadata does not match")
        continue
    }
    if bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        != expectedShortVersion
        || bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        != expectedBundleVersion {
        failures.append(
            "\(expected.identifier): installed version does not match \(expectedShortVersion) (\(expectedBundleVersion))"
        )
        continue
    }
    let executablePath = URL(fileURLWithPath: expected.path)
        .appendingPathComponent("Contents/MacOS/\(expected.executable)").path
    if !FileManager.default.isExecutableFile(atPath: executablePath) {
        failures.append("\(expected.identifier): executable is missing")
        continue
    }

    var matches: [TISInputSource] = []
    for case let source as TISInputSource in enabledSources {
        if stringProperty(source, key: kTISPropertyBundleID) == expected.identifier,
           stringProperty(source, key: kTISPropertyInputSourceID) == expected.identifier {
            matches.append(source)
        }
    }

    if matches.count != 1 {
        failures.append("\(expected.identifier): expected one enabled source, found \(matches.count)")
        continue
    }

    let source = matches[0]
    if !boolProperty(source, key: kTISPropertyInputSourceIsEnabled) {
        failures.append("\(expected.identifier): source is not enabled")
    }
    if !boolProperty(source, key: kTISPropertyInputSourceIsSelectCapable) {
        failures.append("\(expected.identifier): source is not selectable")
    }

    let resolvedPath = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: expected.identifier
    )?.resolvingSymlinksInPath().standardizedFileURL.path
    if resolvedPath != expected.path {
        failures.append(
            "\(expected.identifier): LaunchServices resolved \(resolvedPath ?? "nothing") instead of \(expected.path)"
        )
    }
}

if failures.isEmpty {
    print("PASS: both LinguaFlow input sources are enabled, selectable, and system-resolved")
    exit(0)
}

for failure in failures {
    fputs("FAIL: \(failure)\n", stderr)
}
exit(1)
