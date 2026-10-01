import SwiftUI
import Translation

@available(iOS 18.0, *)
struct OfflineBridge: View {
    @ObservedObject var model: ConversationModel
    @State private var configuration: TranslationSession.Configuration?
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: model.offlineJob?.id) { _, _ in
                guard let job = model.offlineJob else { configuration = nil; return }
                let source = Locale.Language(identifier: job.source.translationCode)
                let target = Locale.Language(identifier: job.target.translationCode)
                if configuration?.source == source && configuration?.target == target {
                    configuration?.invalidate()
                } else { configuration = .init(source: source, target: target) }
            }
            .translationTask(configuration) { @MainActor session in
                guard let job = model.offlineJob else { return }
                do {
                    if job.prepareOnly {
                        try await session.prepareTranslation()
                        model.offlineSucceeded(job, translation: nil)
                    } else {
                        let response = try await session.translate(job.text)
                        model.offlineSucceeded(job, translation: response.targetText)
                    }
                } catch {
                    if !Task.isCancelled { model.offlineFailed(job, error: error) }
                }
            }
    }
}
