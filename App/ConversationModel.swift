import SwiftUI
import AVFoundation

@MainActor
final class ConversationModel: ObservableObject {
    enum Phase { case idle, requestingPermission, listening, translating, speaking }
    @Published var phase: Phase = .idle
    @Published var left = SpokenLanguage.all[0]
    @Published var right = SpokenLanguage.all[1]
    @Published var turns: [Turn] = []
    @Published var partial = ""
    @Published var message: String?
    @Published var offlineJob: OfflineJob?
    @Published var currentSourceIsLeft = true
    @AppStorage("autoSpeak") var autoSpeak = true
    @AppStorage("continuous") var continuous = false
    @AppStorage("offlineASR") var offlineASR = false
    @AppStorage("offlineTranslation") var offlineTranslation = false
    @AppStorage("silenceSeconds") var silence = 0.8
    @AppStorage("hints") var hints = ""
    private let speech = SpeechService()
    private var work: Task<Void, Never>?
    private var activeID: UUID?
    private var began = Date()
    var busy: Bool { phase != .idle }
    var status: String {
        switch phase {
        case .idle: return "点击说话，停顿后自动翻译"
        case .requestingPermission: return "正在申请麦克风与语音识别权限"
        case .listening: return "正在聆听 · 再点一次结束"
        case .translating: return "正在翻译"
        case .speaking: return "正在播报 · 点停止可中断"
        }
    }
    func listen(fromLeft: Bool) {
        stop()
        message = nil; currentSourceIsLeft = fromLeft
        let generation = UUID(); activeID = generation
        phase = .requestingPermission
        work = Task {
            let permitted = await speech.authorize()
            guard !Task.isCancelled, activeID == generation else { return }
            guard permitted else { fail("请在 iPhone 设置中允许麦克风和语音识别权限"); return }
            let source = fromLeft ? left : right
            do {
                try speech.start(language: source, offline: offlineASR,
                    hints: hints.split(separator: "\n").map(String.init), silence: silence,
                    partial: { [weak self] text in self?.partial = text },
                    final: { [weak self] text in self?.translate(text, fromLeft: fromLeft) },
                    error: { [weak self] error in self?.fail(error) })
                phase = .listening
            } catch { fail(error.localizedDescription) }
        }
    }
    func microphone(fromLeft: Bool) {
        if phase == .listening && currentSourceIsLeft == fromLeft { speech.finish() }
        else { listen(fromLeft: fromLeft) }
    }
    func translate(_ text: String, fromLeft: Bool) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stop()
        guard !cleaned.isEmpty else { return }
        message = nil; partial = ""; currentSourceIsLeft = fromLeft
        let source = fromLeft ? left : right; let target = fromLeft ? right : left
        guard source != target else { fail("请选择两种不同的语言"); return }
        let id = UUID(); activeID = id; began = Date()
        turns.append(Turn(id: id, original: cleaned, source: source, target: target))
        if turns.count > 100 { turns.removeFirst() }
        phase = .translating
        if offlineTranslation {
            if #available(iOS 18.0, *) {
                offlineJob = OfflineJob(id: id, text: cleaned, source: source, target: target, prepareOnly: false)
            } else { fail("系统离线翻译需要 iOS 18 或以上；当前系统请使用 DeepSeek") }
            return
        }
        let key = KeyStore.read()
        work = Task {
            do {
                try await DeepSeekClient().translate(text: cleaned, source: source, target: target, key: key) { [weak self] delta in
                    guard let self, self.activeID == id, let index = self.turns.firstIndex(where: { $0.id == id }) else { return }
                    if self.turns[index].firstToken == nil { self.turns[index].firstToken = Date().timeIntervalSince(self.began) }
                    self.turns[index].translation += delta
                }
                guard !Task.isCancelled, activeID == id else { return }
                complete(id: id)
            } catch {
                guard !Task.isCancelled, activeID == id else { return }
                fail(error.localizedDescription)
            }
        }
    }
    func prepareOffline() {
        stop(); message = nil
        guard left != right else { fail("请选择两种不同的语言"); return }
        if #available(iOS 18.0, *) {
            let id = UUID(); activeID = id; phase = .translating
            offlineJob = .init(id: id, text: "", source: left, target: right, prepareOnly: true)
        } else { fail("离线翻译语言包需要 iOS 18 或以上") }
    }
    func offlineSucceeded(_ job: OfflineJob, translation: String?) {
        guard activeID == job.id else { return }
        offlineJob = nil
        if job.prepareOnly { phase = .idle; activeID = nil; message = "此语言组合已准备好；请断网实测离线识别和播报"; return }
        guard let translation, !translation.isEmpty, let index = turns.firstIndex(where: { $0.id == job.id }) else {
            fail("系统未返回译文"); return
        }
        turns[index].translation = translation
        complete(id: job.id)
    }
    func offlineFailed(_ job: OfflineJob, error: Error) {
        guard activeID == job.id else { return }
        fail("离线翻译失败：\(error.localizedDescription)。请检查语言组合是否支持、语言包是否下载")
    }
    private func complete(id: UUID) {
        guard let turnIndex = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[turnIndex].elapsed = Date().timeIntervalSince(began)
        let turn = turns[turnIndex]
        if autoSpeak { speak(turn, resume: true) } else { phase = .idle; resumeIfNeeded() }
    }
    func replay(_ turn: Turn) { stop(); message = nil; speak(turn, resume: false) }
    private func speak(_ turn: Turn, resume: Bool) {
        guard !turn.translation.isEmpty && !turn.failed else { return }
        phase = .speaking
        do {
            try speech.speak(turn.translation, language: turn.target) { [weak self] in
                guard let self else { return }
                self.phase = .idle
                if resume { self.resumeIfNeeded() }
            }
        } catch { fail(error.localizedDescription) }
    }
    private func resumeIfNeeded() {
        guard continuous else { return }
        let direction = currentSourceIsLeft
        work = Task {
            // Leave a gap after playback so the microphone doesn't catch the speaker tail.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            listen(fromLeft: direction)
        }
    }
    func stop() {
        if phase == .translating, let id = activeID, let i = turns.firstIndex(where: { $0.id == id }) {
            turns[i].failed = true
        }
        activeID = nil; work?.cancel(); work = nil
        speech.stop(); speech.cancelSpeech(); offlineJob = nil
        partial = ""; phase = .idle
    }
    private func fail(_ text: String) { stop(); message = text }
    func clear() { stop(); turns.removeAll() }
}
