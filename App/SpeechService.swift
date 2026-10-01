import AVFoundation
import Speech

@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private let synthesizer = AVSpeechSynthesizer()
    private var hasTap = false
    private var generation = UUID()
    private var lastVoice = Date()
    private var lastText = Date()
    private var started = Date()
    private var heardSpeech = false
    private var finalizing = false
    private var timer: Timer?
    private var text = ""
    private var onPartial: ((String) -> Void)?
    private var onFinal: ((String) -> Void)?
    private var onError: ((String) -> Void)?
    private var onSpoken: (() -> Void)?
    private var currentUtterance: AVSpeechUtterance?

    override init() { super.init(); synthesizer.delegate = self }
    func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let mic = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        return speech && mic
    }
    func start(language: SpokenLanguage, offline: Bool, hints: [String], silence: Double,
               partial: @escaping (String) -> Void, final: @escaping (String) -> Void,
               error: @escaping (String) -> Void) throws {
        stop()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.id)), recognizer.isAvailable else {
            throw TranslatorError.message("此语言的系统语音识别当前不可用，请尝试文字输入")
        }
        if offline && !recognizer.supportsOnDeviceRecognition {
            throw TranslatorError.message("此设备未提供该语言的离线识别；可关闭离线识别或使用文字输入")
        }
        self.recognizer = recognizer
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = offline
        req.taskHint = .dictation
        req.contextualStrings = Array(hints.prefix(100))
        request = req
        onPartial = partial; onFinal = final; onError = error
        text = ""; started = Date(); lastVoice = started; lastText = started; heardSpeech = false; finalizing = false
        let token = generation
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 && format.channelCount > 0 else { stop(); throw TranslatorError.message("麦克风不可用") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
            let rms = sqrt(sum / Float(buffer.frameLength))
            if rms > 0.012 {
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.lastVoice = Date(); self.heardSpeech = true
                }
            }
        }
        hasTap = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, failure in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if let result {
                    let updated = result.bestTranscription.formattedString
                    if updated != self.text { self.lastText = Date() }
                    self.text = updated; self.onPartial?(updated)
                    if result.isFinal { self.deliverFinal(); return }
                }
                if failure != nil {
                    if self.finalizing && !self.text.isEmpty { self.deliverFinal() }
                    else { self.fail("语音识别中断，请检查网络、语言支持或麦克风权限") }
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                let now = Date()
                if !self.text.isEmpty && self.heardSpeech && now.timeIntervalSince(self.lastVoice) > silence && now.timeIntervalSince(self.lastText) > 0.25 {
                    self.finish()
                } else if now.timeIntervalSince(self.started) > 50 {
                    if self.text.isEmpty { self.fail("未识别到语音，请再试一次") } else { self.finish() }
                }
            }
        }
        engine.prepare()
        do { try engine.start() } catch { stop(); throw error }
    }
    func finish() {
        guard !finalizing else { return }
        finalizing = true
        timer?.invalidate()
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        let token = generation
        // Let the recognizer revise the last words before cancellation; bounded fallback.
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.deliverFinal()
            }
        }
    }
    private func deliverFinal() {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = onFinal
        stop()
        callback?(result)
    }
    private func fail(_ message: String) { let callback = onError; stop(); callback?(message) }
    func stop() {
        generation = UUID()
        timer?.invalidate(); timer = nil
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil; recognizer = nil
        onPartial = nil; onFinal = nil; onError = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func speak(_ text: String, language: SpokenLanguage, completion: @escaping () -> Void) throws {
        cancelSpeech()
        guard let voice = AVSpeechSynthesisVoice(language: language.id) else {
            throw TranslatorError.message("未安装该语言的系统声音，请在 iPhone 辅助功能中下载声音")
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        onSpoken = completion
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }
    func cancelSpeech() { onSpoken = nil; currentUtterance = nil; synthesizer.stopSpeaking(at: .immediate) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.currentUtterance = nil
            let callback = self.onSpoken; self.onSpoken = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            callback?()
        }
    }
}
