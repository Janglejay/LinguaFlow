import AppKit
import Foundation
import LinguaFlowRime

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    private(set) var runtime: RimeRuntime?

    private init() {}

    func start() throws {
        guard runtime == nil else { return }
        guard let resources = Bundle.main.resourceURL else {
            throw EnvironmentError.missingBundleResources
        }

        let sharedData = resources.appendingPathComponent("Rime", isDirectory: true)
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let userData = appSupport
            .appendingPathComponent("LinguaFlow", isDirectory: true)
            .appendingPathComponent("Rime", isDirectory: true)

        runtime = try RimeRuntime(
            sharedDataDirectory: sharedData,
            userDataDirectory: userData
        )
    }

    func makeEngine() throws -> RimeEngine {
        guard let runtime else {
            throw EnvironmentError.rimeNotStarted
        }
        return try RimeEngine(runtime: runtime)
    }
}

enum EnvironmentError: LocalizedError {
    case missingBundleResources
    case rimeNotStarted

    var errorDescription: String? {
        switch self {
        case .missingBundleResources: "LinguaFlow 找不到输入法资源。"
        case .rimeNotStarted: "LinguaFlow 的拼音引擎尚未启动。"
        }
    }
}
