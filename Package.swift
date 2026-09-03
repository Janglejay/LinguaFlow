// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LinguaFlow",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .library(name: "LinguaFlowCore", targets: ["LinguaFlowCore"]),
        .library(name: "LinguaFlowRime", targets: ["LinguaFlowRime"]),
        .executable(name: "LinguaFlowIME", targets: ["LinguaFlowIME"]),
        .executable(name: "LinguaFlowSetup", targets: ["LinguaFlowSetup"]),
        .executable(name: "linguaflow-core-checks", targets: ["LinguaFlowCoreChecks"]),
        .executable(name: "linguaflow-rime-checks", targets: ["LinguaFlowRimeChecks"]),
        .executable(name: "linguaflow-translation-checks", targets: ["LinguaFlowTranslationChecks"]),
    ],
    targets: [
        .target(name: "LinguaFlowCore"),
        .target(
            name: "LinguaFlowRimeBridge",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/opt/librime/include"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L/opt/homebrew/opt/librime/lib",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/opt/homebrew/opt/librime/lib",
                ]),
                .linkedLibrary("rime"),
            ]
        ),
        .target(
            name: "LinguaFlowRime",
            dependencies: ["LinguaFlowRimeBridge"]
        ),
        .executableTarget(
            name: "LinguaFlowIME",
            dependencies: ["LinguaFlowCore", "LinguaFlowRime"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("InputMethodKit"),
            ]
        ),
        .executableTarget(
            name: "LinguaFlowSetup",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Translation"),
            ]
        ),
        .executableTarget(
            name: "LinguaFlowCoreChecks",
            dependencies: ["LinguaFlowCore"]
        ),
        .executableTarget(
            name: "LinguaFlowRimeChecks",
            dependencies: ["LinguaFlowRime"]
        ),
        .executableTarget(
            name: "LinguaFlowTranslationChecks",
            dependencies: ["LinguaFlowCore"],
            linkerSettings: [
                .linkedFramework("Translation"),
            ]
        ),
        .testTarget(
            name: "LinguaFlowCoreTests",
            dependencies: ["LinguaFlowCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
