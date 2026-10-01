import SwiftUI
import AVFoundation

@MainActor
final class ConversationModel: ObservableObject {
    enum Phase { case idle, requestingPermission, recording, finishing, saving }
    @Published var phase: Phase = .idle
    @Published var left = SpokenLanguage.all[0]
    @Published var right = SpokenLanguage.all[1]
    @Published var turns: [Turn] = []
    @Published var partials: [RecognitionCandidate] = []
    @Published var elapsed = 0.0
    @Published var level = 0.0
    @Published var inputDescription = ""
    @Published var message: String?
    @Published var awaitingSaveChoice = false
    @Published var speaking = false
    @Published var currentSourceIsLeft = true
    @AppStorage("v2AutoSpeak") var autoSpeak = false
    @AppStorage("offlineASR") var offlineASR = false
    @AppStorage("v2SilenceSeconds") var silence = 1.3
    @AppStorage("hints") var hints = ""
    private let speech = SpeechService()
    private var authorization: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    private var workerID = UUID()
    private var finishDeadline: Task<Void, Never>?
    private var speechQueue: [UUID] = []
    private var queue: [UUID] = []
    private var revision: [UUID: UUID] = [:]
    private var sessionID = UUID()
    private var sessionDate = Date()
    private var audioURL: URL?
    private var asrDrained = true
    private var archiveHasAudioError = false
    private var currentTranslation: UUID?
    private var began = Date()
    init() {}
    var busy: Bool { phase != .idle }
    var translatingCount: Int { turns.filter { $0.pending && !$0.needsConfirmation }.count }
    var canSave: Bool { phase == .idle && audioURL != nil && !archiveHasAudioError && worker == nil }
    var hasUnsavedSession: Bool { audioURL != nil }
    var status: String {
        switch phase {
        case .idle: return audioURL == nil ? "点击开始，双方自然轮流说话" : "对话已结束 · 可保存录音和文字到本机"
        case .requestingPermission: return "正在申请麦克风与语音识别权限"
        case .recording: return speaking ? "正在播报 · 录音继续，识别暂缓" : "持续录音 · 自动识别双语 · 翻译队列 \(translatingCount)"
        case .finishing: return "正在完成最后的识别与翻译"
        case .saving: return "正在压缩录音并保存到本机"
        }
    }
    func startConversation() {
        guard phase == .idle else { return }
        guard audioURL == nil else { awaitingSaveChoice = true; return }
        guard left != right else { message = "请选择两种不同的语言"; return }
        workerID = UUID(); worker?.cancel(); worker = nil; queue.removeAll(); revision.removeAll()
        message = nil; turns.removeAll(); partials = []; elapsed = 0; level = 0
        sessionID = UUID(); sessionDate = Date(); let token = sessionID
        archiveHasAudioError = false; phase = .requestingPermission
        authorization = Task {
            let allowed = await speech.authorize()
            guard !Task.isCancelled, sessionID == token, phase == .requestingPermission else { return }
            guard allowed else { phase = .idle; message = "请在 iPhone 设置中允许麦克风和语音识别"; return }
            do {
                let url = try LocalArchive.temporaryAudio(); audioURL = url; asrDrained = false
                try speech.start(left: left, right: right, offline: offlineASR,
                    hints: hints.split(separator: "\n").map(String.init), silence: silence, audioURL: url,
                    partial: { [weak self] in self?.partials = $0 },
                    segment: { [weak self] decision, start, end in self?.receive(decision, start: start, end: end) },
                    level: { [weak self] duration, level, input in
                        self?.elapsed = duration; self?.level = level
                        if let input { self?.inputDescription = input }
                    }, warning: { [weak self] in self?.message = $0 })
                phase = .recording
            } catch {
                speech.cancel(); if let url = audioURL { try? FileManager.default.removeItem(at: url) }
                audioURL = nil; phase = .idle; message = error.localizedDescription
            }
        }
    }
    func endConversation() {
        if phase == .requestingPermission { authorization?.cancel(); sessionID = UUID(); phase = .idle; return }
        guard phase == .recording else { return }
        phase = .finishing; speechQueue.removeAll(); speaking = false
        let result = speech.finish { [weak self] in self?.asrDrained = true; self?.finishIfReady() }
        elapsed = result.0; level = 0; partials = []
        if let error = result.1 { archiveHasAudioError = true; message = error }
        finishDeadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled, let self, self.phase == .finishing else { return }
            self.workerID = UUID(); self.worker?.cancel(); self.worker = nil; self.queue.removeAll(); self.speech.cancel()
            for index in self.turns.indices where self.turns[index].pending && !self.turns[index].needsConfirmation {
                self.turns[index].pending = false; self.turns[index].failed = true
            }
            self.asrDrained = true; self.message = "部分翻译尚未完成，录音仍可保存后核对"
            self.finishIfReady()
        }
        finishIfReady()
    }
    private func receive(_ decision: RecognitionDecision, start: Double, end: Double) {
        guard let candidate = decision.candidate else { return }
        let target = candidate.language == left ? right : left
        let records = decision.alternatives.map { CandidateRecord(language: $0.language, text: $0.text, confidence: $0.confidence) }
        var turn = Turn(id: UUID(), original: candidate.text, source: candidate.language, target: target)
        turn.startedAt = start; turn.endedAt = end; turn.needsConfirmation = decision.needsConfirmation
        turn.alternatives = records; turn.pending = !decision.needsConfirmation
        if decision.needsConfirmation { turn.recognitionNote = "语言或原文可靠性不足，请核对后翻译" }
        turns.append(turn)
        turns.sort { $0.startedAt < $1.startedAt }
        if !turn.needsConfirmation { enqueue(turn.id) }
    }
    func confirm(id: UUID, original: String, language: SpokenLanguage) {
        guard let index = turns.firstIndex(where: { $0.id == id }), phase != .saving else { return }
        let cleaned = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        turns[index].original = cleaned; turns[index].source = language
        turns[index].target = language == left ? right : left
        turns[index].needsConfirmation = false; turns[index].recognitionNote = nil
        turns[index].translation = ""; turns[index].elapsed = nil; turns[index].firstToken = nil; turns[index].failed = false
        enqueue(id)
    }
    func translateTyped(_ text: String) {
        guard phase != .saving else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let source = currentSourceIsLeft ? left : right
        let target = currentSourceIsLeft ? right : left
        guard source != target else { message = "请选择两种不同的语言"; return }
        var turn = Turn(id: UUID(), original: cleaned, source: source, target: target)
        turn.startedAt = elapsed; turn.endedAt = elapsed
        turns.append(turn); enqueue(turn.id)
    }
    private func enqueue(_ id: UUID) {
        guard let i = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[i].pending = true; revision[id] = UUID()
        if !queue.contains(id) { queue.append(id) }
        startWorker()
    }
    private func startWorker() {
        guard worker == nil else { return }
        let token = UUID(); workerID = token
        worker = Task { [weak self] in
            guard let self else { return }
            while !self.queue.isEmpty && !Task.isCancelled && self.workerID == token {
                let id = self.queue.removeFirst()
                guard let index = self.turns.firstIndex(where: { $0.id == id }) else { continue }
                let turn = self.turns[index]; let version = self.revision[id]
                self.currentTranslation = id; self.began = Date()
                let contextTurns = self.turns.prefix(index).filter { !$0.failed && !$0.pending && !$0.needsConfirmation }.suffix(4)
                let context = contextTurns.map { "\($0.source.name): \($0.original)\n\($0.target.name): \($0.translation)" }.joined(separator: "\n").prefix(1600)
                do {
                    try await DeepSeekClient().translate(text: turn.original, source: turn.source, target: turn.target,
                        key: KeyStore.read(), context: String(context)) { [weak self] delta in
                        guard let self, self.revision[id] == version, let i = self.turns.firstIndex(where: { $0.id == id }) else { return }
                        if self.turns[i].firstToken == nil { self.turns[i].firstToken = Date().timeIntervalSince(self.began) }
                        self.turns[i].translation += delta
                    }
                    guard !Task.isCancelled else { break }
                    if self.revision[id] == version, let i = self.turns.firstIndex(where: { $0.id == id }) {
                        self.turns[i].elapsed = Date().timeIntervalSince(self.began); self.turns[i].pending = false
                        if self.autoSpeak && self.phase == .recording { self.speechQueue.append(id); self.playNext() }
                    }
                } catch {
                    guard !Task.isCancelled else { break }
                    if self.revision[id] == version, let i = self.turns.firstIndex(where: { $0.id == id }) {
                        self.turns[i].failed = true; self.turns[i].pending = false
                        self.message = error.localizedDescription
                    }
                }
            }
            guard self.workerID == token else { return }
            self.currentTranslation = nil; self.worker = nil; self.finishIfReady()
        }
    }
    private func playNext() {
        guard !speaking, phase == .recording, autoSpeak, !speechQueue.isEmpty else { return }
        let id = speechQueue.removeFirst()
        guard let turn = turns.first(where: { $0.id == id }), !turn.failed, !turn.needsConfirmation else { playNext(); return }
        speaking = true
        do { try speech.speak(turn.translation, language: turn.target) { [weak self] in self?.speaking = false; self?.playNext() } }
        catch { speaking = false; message = error.localizedDescription }
    }
    func replay(_ turn: Turn) {
        guard phase == .idle, !turn.translation.isEmpty, !turn.failed, !turn.needsConfirmation else { return }
        speaking = true
        do { try speech.speak(turn.translation, language: turn.target) { [weak self] in self?.speaking = false } }
        catch { speaking = false; message = error.localizedDescription }
    }
    private func finishIfReady() {
        guard phase == .finishing, asrDrained, worker == nil, queue.isEmpty else { return }
        finishDeadline?.cancel(); finishDeadline = nil; phase = .idle; awaitingSaveChoice = true
    }
    func saveSession() {
        guard canSave, worker == nil, let url = audioURL else { message = "请等翻译完成后再保存"; return }
        phase = .saving; awaitingSaveChoice = false
        let metadata = SavedConversation(id: sessionID, date: sessionDate, duration: elapsed,
            left: left, right: right, turns: turns, audioFile: "audio.m4a")
        Task {
            do { try await LocalArchive.save(audio: url, conversation: metadata); audioURL = nil; message = "已保存到本机：录音与双语文字" }
            catch { message = error.localizedDescription }
            phase = .idle
        }
    }
    func discardRecording() {
        guard phase == .idle else { return }
        if let url = audioURL { try? FileManager.default.removeItem(at: url) }
        audioURL = nil; awaitingSaveChoice = false; message = "录音已删除；屏幕上的文字仍可查看"
    }
    func clear() {
        guard phase == .idle else { return }
        if audioURL != nil { awaitingSaveChoice = true; return }
        workerID = UUID(); worker?.cancel(); worker = nil; queue.removeAll(); revision.removeAll()
        speech.cancelSpeech(); speaking = false; turns.removeAll(); message = nil
    }
}
