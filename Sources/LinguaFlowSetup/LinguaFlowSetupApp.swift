import SwiftUI
import Translation

@main
struct LinguaFlowSetupApp: App {
    var body: some Scene {
        WindowGroup("LinguaFlow 设置") {
            TranslationSetupView()
                .frame(width: 480, height: 300)
        }
        .windowResizability(.contentSize)
    }
}

private struct TranslationSetupView: View {
    @State private var configuration: TranslationSession.Configuration?
    @State private var isPreparing = false
    @State private var status = "尚未检查本地翻译模型"

    private let source = Locale.Language(identifier: "zh-Hans")
    private let target = Locale.Language(identifier: "en")

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LinguaFlow")
                .font(.largeTitle.bold())
            Text("下载 Apple 的中文与英语翻译模型后，长句翻译会完全在这台 Mac 上处理。")
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
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(28)
        .translationTask(configuration) { session in
            guard isPreparing else { return }
            do {
                try await session.prepareTranslation()
                let response = try await session.translate("你好，很高兴认识你。")
                status = "本地翻译已就绪：\(response.targetText)"
            } catch {
                status = "准备失败：\(error.localizedDescription)"
            }
            isPreparing = false
        }
    }
}
