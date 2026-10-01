import AVFoundation
import Speech

// Audio tap owns its buffers; the serial writer never reads a recycled engine buffer.
private final class CaptureSink {
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "conversation.local-audio")
    private var file: AVAudioFile?
    private var requests: [SFSpeechAudioBufferRecognitionRequest] = []
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollFrames = 0
    private var frames: Int64 = 0
    private let rate: Double
    private var writeError: String?
    init(url: URL, format: AVAudioFormat) throws {
        rate = format.sampleRate
        file = try AVAudioFile(forWriting: url, settings: format.settings,
                               commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    }
    var seconds: Double { lock.lock(); defer { lock.unlock() }; return Double(frames) / rate }
    func replaceRequests(_ incoming: [SFSpeechAudioBufferRecognitionRequest], prime: Bool) {
        lock.lock(); defer { lock.unlock() }
        if prime { for buffer in preRoll { for request in incoming { request.append(buffer) } } }
        requests = incoming
    }
    func clearPreRoll() { lock.lock(); preRoll.removeAll(); preRollFrames = 0; lock.unlock() }
    func consume(_ buffer: AVAudioPCMBuffer) -> (Double, Double, Double) {
        var energy = 0.0
        var clipped = 0
        if let channel = buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) {
                let sample = Double(channel[i]); energy += sample * sample
                if abs(sample) >= 0.98 { clipped += 1 }
            }
        }
        let count = max(Int(buffer.frameLength), 1)
        let rms = sqrt(energy / Double(count))
        let owned = Self.copy(buffer)
        lock.lock()
        frames += Int64(buffer.frameLength)
        let time = Double(frames) / rate
        for request in requests { request.append(buffer) }
        if let owned {
            preRoll.append(owned); preRollFrames += Int(owned.frameLength)
            while preRollFrames > Int(rate * 0.25), preRoll.count > 1 {
                preRollFrames -= Int(preRoll.removeFirst().frameLength)
            }
            writer.async { [self] in
                do { try file?.write(from: owned) }
                catch { writeError = "本地录音写入失败，请检查存储空间" }
            }
        }
        lock.unlock()
        return (time, rms, Double(clipped) / Double(count))
    }
    func close() -> String? {
        replaceRequests([], prime: false)
        return writer.sync { file = nil; return writeError }
    }
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let result = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        result.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let target = UnsafeMutableAudioBufferListPointer(result.mutableAudioBufferList)
        for i in 0..<source.count {
            guard let from = source[i].mData, let to = target[i].mData else { return nil }
            memcpy(to, from, Int(source[i].mDataByteSize))
        }
        return result
    }
}

@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private final class Slot {
        let language: SpokenLanguage
        let recognizer: SFSpeechRecognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        var task: SFSpeechRecognitionTask?
        var text = ""
        var confidence = 0.0
        var final = false
        var completed = false
        init(language: SpokenLanguage, recognizer: SFSpeechRecognizer) { self.language = language; self.recognizer = recognizer }
    }
    private final class Batch {
        let id = UUID()
        let start: Double
        var end: Double = 0
        var lastText: Double
        var slots: [Slot]
        var endpoint = AdaptiveEndpoint()
        var ending = false
        var deadline: Task<Void, Never>?
        init(start: Double, slots: [Slot]) { self.start = start; self.lastText = start; self.slots = slots }
    }
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var sink: CaptureSink?
    private var batches: [UUID: Batch] = [:]
    private var active: Batch?
    private var timer: Timer?
    private var hasTap = false
    private var recording = false
    private var playbackMuted = false
    private var generation = UUID()
    private var languages: [SpokenLanguage] = []
    private var hints: [String] = []
    private var offline = false
    private var silence = 1.3
    private var onPartial: (([RecognitionCandidate]) -> Void)?
    private var onSegment: ((RecognitionDecision, Double, Double) -> Void)?
    private var onLevel: ((Double, Double, String?) -> Void)?
    private var onWarning: ((String) -> Void)?
    private var onDrained: (() -> Void)?
    private var onSpoken: (() -> Void)?
    private var currentUtterance: AVSpeechUtterance?
    private var warningTime = 0.0
    private var meterTime = 0.0
    private var restartTask: Task<Void, Never>?
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
    func start(left: SpokenLanguage, right: SpokenLanguage, offline: Bool, hints: [String], silence: Double,
               audioURL: URL, partial: @escaping ([RecognitionCandidate]) -> Void,
               segment: @escaping (RecognitionDecision, Double, Double) -> Void,
               level: @escaping (Double, Double, String?) -> Void,
               warning: @escaping (String) -> Void) throws {
        cancel()
        guard left != right else { throw TranslatorError.message("请选择两种不同的语言") }
        for language in [left, right] {
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.id)), recognizer.isAvailable else {
                throw TranslatorError.message("\(language.name)的系统语音识别不可用，无法开启该双语组合")
            }
            if offline && !recognizer.supportsOnDeviceRecognition {
                throw TranslatorError.message("此手机未提供\(language.name)的设备端识别，请关闭离线识别或更换语言")
            }
        }
        self.languages = [left, right]; self.offline = offline; self.hints = Array(hints.prefix(100))
        self.silence = silence; onPartial = partial; onSegment = segment; onLevel = level; onWarning = warning
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(48000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw TranslatorError.message("麦克风不可用") }
        let capture = try CaptureSink(url: audioURL, format: format)
        sink = capture; recording = true; playbackMuted = false; warningTime = 0; meterTime = 0
        let token = generation
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let sample = capture.consume(buffer)
            Task { @MainActor in
                guard let self, self.generation == token, self.recording else { return }
                self.observe(time: sample.0, rms: sample.1, clipped: sample.2)
            }
        }
        hasTap = true
        beginBatch()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        engine.prepare()
        do { try engine.start() } catch { cancel(); throw error }
        let route = session.currentRoute.inputs.first?.portName ?? "麦克风"
        level(0, 0, "\(route) · \(Int(format.sampleRate)) Hz")
    }
    private func beginBatch() {
        guard recording, !playbackMuted, let sink else { return }
        let slots = languages.compactMap { language -> Slot? in
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.id)) else { return nil }
            let slot = Slot(language: language, recognizer: recognizer)
            slot.request.shouldReportPartialResults = true
            slot.request.requiresOnDeviceRecognition = offline
            slot.request.taskHint = .dictation
            slot.request.contextualStrings = hints
            return slot
        }
        let batch = Batch(start: max(0, sink.seconds - 0.25), slots: slots)
        batches[batch.id] = batch; active = batch
        for slot in slots {
            slot.task = slot.recognizer.recognitionTask(with: slot.request) { [weak self, weak batch, weak slot] result, error in
                Task { @MainActor in
                    guard let self, let batch, let slot, self.batches[batch.id] != nil else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        if text != slot.text { batch.lastText = self.sink?.seconds ?? batch.end }
                        slot.text = text
                        let segments = result.bestTranscription.segments
                        slot.confidence = segments.isEmpty ? 0 : segments.map { Double($0.confidence) }.reduce(0, +) / Double(segments.count)
                        slot.final = result.isFinal
                        if result.isFinal { slot.completed = true }
                    }
                    if error != nil {
                        slot.completed = true
                        if slot.text.isEmpty { self.onWarning?("\(slot.language.name)识别中断；请检查网络或设备端语言支持") }
                    }
                    if self.active?.id == batch.id { self.onPartial?(self.candidates(batch, evidence: false)) }
                    if batch.slots.allSatisfy(\.completed) {
                        if !batch.ending { self.endBatch(batch, restart: self.recording && !self.playbackMuted) }
                        self.deliver(batch)
                    }
                }
            }
        }
        sink.replaceRequests(slots.map(\.request), prime: true)
        onPartial?([])
    }
    private func observe(time: Double, rms: Double, clipped: Double) {
        if !playbackMuted { active?.endpoint.observe(rms: rms, time: time) }
        let level = min(1, max(0, (20 * log10(max(rms, 0.00001)) + 60) / 60))
        if time - meterTime >= 0.1 { meterTime = time; onLevel?(time, level, nil) }
        if clipped > 0.015 && time - warningTime > 8 {
            warningTime = time; onWarning?("声音过响可能失真，请降低外放音量或拉开距离；增大音量不等于提高识别率")
        }
    }
    private func tick() {
        guard recording, !playbackMuted, let batch = active, let sink else { return }
        let now = sink.seconds
        let hasText = batch.slots.contains { !$0.text.isEmpty }
        let noTranscript = batch.endpoint.heardVoice && now - batch.endpoint.lastVoice > silence + 4
        if batch.endpoint.shouldEnd(now: now, lastText: batch.lastText, silence: silence, hasText: hasText)
            || now - batch.start >= 28 || noTranscript {
            endBatch(batch, restart: true)
        }
    }
    private func endBatch(_ batch: Batch, restart: Bool) {
        guard !batch.ending else { return }
        batch.ending = true; batch.end = sink?.seconds ?? batch.start
        if active?.id == batch.id { sink?.replaceRequests([], prime: false); active = nil }
        for slot in batch.slots { slot.request.endAudio() }
        // Final recognizer revisions are important; don't translate the first partial guess.
        batch.deadline = Task { [weak self, weak batch] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled, let self, let batch, self.batches[batch.id] != nil else { return }
            self.deliver(batch)
        }
        if restart {
            if batch.slots.allSatisfy({ $0.completed && $0.text.isEmpty }) {
                let token = generation
                restartTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled, let self, self.generation == token, self.recording, !self.playbackMuted else { return }
                    self.beginBatch()
                }
            } else { beginBatch() }
        }
    }
    private func candidates(_ batch: Batch, evidence: Bool = true) -> [RecognitionCandidate] {
        batch.slots.filter { !$0.text.isEmpty }.map {
            .init(language: $0.language, text: $0.text, confidence: $0.confidence,
                  languageEvidence: evidence ? RecognitionPolicy.evidence(text: $0.text, language: $0.language) : 0, isFinal: $0.final)
        }
    }
    private func deliver(_ batch: Batch) {
        guard batches.removeValue(forKey: batch.id) != nil else { return }
        batch.deadline?.cancel()
        let decision = RecognitionPolicy.decide(candidates(batch))
        for slot in batch.slots { slot.task?.cancel() }
        if decision.candidate != nil { onSegment?(decision, batch.start, batch.end) }
        if !recording && batches.isEmpty { let done = onDrained; onDrained = nil; done?() }
    }
    func finish(completion: @escaping () -> Void) -> (Double, String?) {
        recording = false; restartTask?.cancel(); restartTask = nil; timer?.invalidate(); timer = nil
        cancelSpeech()
        let duration = sink?.seconds ?? 0
        if let active { endBatch(active, restart: false) }
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        let error = sink?.close()
        onDrained = completion
        if batches.isEmpty { onDrained = nil; completion() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (duration, error)
    }
    func cancel() {
        generation = UUID(); recording = false; restartTask?.cancel(); restartTask = nil; timer?.invalidate(); timer = nil
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        for batch in batches.values {
            batch.deadline?.cancel(); for slot in batch.slots { slot.request.endAudio(); slot.task?.cancel() }
        }
        batches.removeAll(); active = nil; _ = sink?.close(); sink = nil
        onPartial = nil; onSegment = nil; onLevel = nil; onWarning = nil; onDrained = nil
        cancelSpeech()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func speak(_ text: String, language: SpokenLanguage, completion: @escaping () -> Void) throws {
        cancelSpeech()
        guard let voice = AVSpeechSynthesisVoice(language: language.id) else { throw TranslatorError.message("系统没有该语言的声音，请在辅助功能中下载") }
        if recording {
            playbackMuted = true
            if let active { endBatch(active, restart: false) }
        } else {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        }
        onSpoken = completion
        let utterance = AVSpeechUtterance(string: text); utterance.voice = voice
        currentUtterance = utterance; synthesizer.speak(utterance)
    }
    func cancelSpeech() { onSpoken = nil; currentUtterance = nil; synthesizer.stopSpeaking(at: .immediate) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance === utterance else { return }
            self.currentUtterance = nil
            let callback = self.onSpoken; self.onSpoken = nil
            if self.recording {
                let token = self.generation
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard self.recording, self.generation == token else { return }
                self.sink?.clearPreRoll(); self.playbackMuted = false; self.beginBatch()
            } else { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
            callback?()
        }
    }
}
