import AppKit
import SwiftUI
import Translation

@MainActor
private final class SetupAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct LinguaFlowSetupApp: App {
    @NSApplicationDelegateAdaptor(SetupAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("LinguaFlow 设置", id: "setup") {
            TranslationSetupView()
                .frame(width: 480, height: 300)
        }
        .windowResizability(.contentSize)
    }
}

private struct TranslationSetupView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var configuration: TranslationSession.Configuration?
    @State private var isPreparing = false
    @State private var status = "尚未检查本地翻译模型"

    private let source = Locale.Language(identifier: "zh-Hans")
    private let target = Locale.Language(identifier: "en")

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LinguaFlow")
                .font(.largeTitle.bold())
            Text("下载 Apple 的中文与英语翻译模型后，中译英与英译中都会完全在这台 Mac 上处理。")
                .foregroundStyle(.secondary)

            Label(status, systemImage: isPreparing ? "arrow.down.circle" : "character.book.closed")

            HStack {
                Button(isPreparing ? "正在准备…" : "准备本地翻译") {
                    isPreparing = true
                    status = "等待 Apple 的下载确认…"
                    configuration = TranslationSession.Configuration(source: source, target: target)
                    configuration?.invalidate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPreparing)

                Button("完成") {
                    dismissWindow(id: "setup")
                }
            }
        }
        .padding(28)
        .translationTask(configuration) { session in
            guard isPreparing else { return }
            do {
                try await session.prepareTranslation()
                let response = try await session.translate("你好，很高兴认识你。")
                let reverseSession = TranslationSession(installedSource: target, target: source)
                let reverseResponse = try await reverseSession.translate("Hello, nice to meet you.")
                status = "双向翻译已就绪：\(response.targetText) / \(reverseResponse.targetText)"
            } catch {
                status = "准备失败：\(error.localizedDescription)"
            }
            isPreparing = false
        }
    }
}
