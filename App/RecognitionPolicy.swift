import Foundation
import NaturalLanguage

struct RecognitionCandidate: Identifiable {
    var id: String { language.id }
    let language: SpokenLanguage
    let text: String
    let confidence: Double
    let languageEvidence: Double
    let isFinal: Bool
    var score: Double { confidence * 0.65 + languageEvidence * 0.35 }
}
struct RecognitionDecision {
    let candidate: RecognitionCandidate?
    let alternatives: [RecognitionCandidate]
    let needsConfirmation: Bool
}
enum RecognitionPolicy {
    static func evidence(text: String, language: SpokenLanguage) -> Double {
        let detector = NLLanguageRecognizer()
        detector.processString(text)
        let expected = language.translationCode.hasPrefix("zh") ? "zh-Hans" : language.translationCode
        let hypotheses = detector.languageHypotheses(withMaximum: 6)
        if expected == "zh-Hans" {
            return hypotheses.filter { $0.key.rawValue.hasPrefix("zh") }.map(\.value).max() ?? 0
        }
        return hypotheses.first { $0.key.rawValue == expected }?.value ?? 0
    }
    static func decide(_ candidates: [RecognitionCandidate]) -> RecognitionDecision {
        let valid = candidates.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.score > $1.score }
        guard let first = valid.first else { return .init(candidate: nil, alternatives: [], needsConfirmation: true) }
        let margin = valid.count > 1 ? first.score - valid[1].score : 0
        let substantial = first.text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count >= 4
        // Confidence from separate monolingual recognizers isn't calibrated. Require independent
        // text-language evidence AND a margin; ambiguous short speech must be reviewed.
        let certain = valid.count == 2 && first.isFinal && substantial && first.confidence >= 0.55
            && first.languageEvidence >= 0.65 && margin >= 0.18
        return .init(candidate: first, alternatives: valid, needsConfirmation: !certain)
    }
}

struct AdaptiveEndpoint {
    private(set) var noise: Double = 0.002
    private(set) var lastVoice = 0.0
    private(set) var heardVoice = false
    private var speechFrames = 0
    mutating func observe(rms: Double, time: Double) {
        let threshold = max(0.0035, min(noise * 3.2, 0.035))
        if rms > threshold {
            speechFrames += 1
            if speechFrames >= 3 { heardVoice = true; lastVoice = time }
        } else {
            speechFrames = 0
            if !heardVoice || time - lastVoice > 0.4 { noise = noise * 0.98 + min(rms, 0.015) * 0.02 }
        }
    }
    func shouldEnd(now: Double, lastText: Double, silence: Double, hasText: Bool) -> Bool {
        heardVoice && hasText && now - lastVoice >= silence && now - lastText >= 0.65
    }
}
