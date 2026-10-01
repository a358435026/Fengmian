import XCTest
@testable import ConversationTranslator

final class RecognitionPolicyTests: XCTestCase {
    private let english = SpokenLanguage.all[1]
    private let chinese = SpokenLanguage.all[0]
    func testClearLanguageEvidenceCanSelectDirection() {
        let d = RecognitionPolicy.decide([
            .init(language: english, text: "Please send the invoice tomorrow", confidence: 0.88, languageEvidence: 0.95, isFinal: true),
            .init(language: chinese, text: "普利森的英沃斯", confidence: 0.31, languageEvidence: 0.92, isFinal: true)])
        XCTAssertEqual(d.candidate?.language, english)
        XCTAssertFalse(d.needsConfirmation)
    }
    func testSimilarConfidenceNeedsConfirmation() {
        let d = RecognitionPolicy.decide([
            .init(language: english, text: "Send the invoice", confidence: 0.8, languageEvidence: 0.9, isFinal: true),
            .init(language: chinese, text: "新的发票", confidence: 0.78, languageEvidence: 0.95, isFinal: true)])
        XCTAssertTrue(d.needsConfirmation)
    }
    func testSingleRecognizerOrPartialCannotBeCalledAutomaticDetection() {
        let c = RecognitionCandidate(language: english, text: "Send the invoice", confidence: 0.99, languageEvidence: 0.99, isFinal: true)
        XCTAssertTrue(RecognitionPolicy.decide([c]).needsConfirmation)
        let partial = RecognitionCandidate(language: english, text: "Send the invoice", confidence: 0.99, languageEvidence: 0.99, isFinal: false)
        let other = RecognitionCandidate(language: chinese, text: "新的", confidence: 0.1, languageEvidence: 0.1, isFinal: true)
        XCTAssertTrue(RecognitionPolicy.decide([partial, other]).needsConfirmation)
    }
    func testShortOrZeroConfidenceSpeechNeedsConfirmation() {
        let low = RecognitionCandidate(language: english, text: "Please send it tomorrow", confidence: 0, languageEvidence: 0.99, isFinal: true)
        XCTAssertTrue(RecognitionPolicy.decide([low]).needsConfirmation)
        let short = RecognitionCandidate(language: english, text: "No", confidence: 0.99, languageEvidence: 0.99, isFinal: true)
        XCTAssertTrue(RecognitionPolicy.decide([short]).needsConfirmation)
    }
    func testEndpointDoesNotEndDuringVoiceOrUnstableText() {
        var vad = AdaptiveEndpoint()
        for i in 0..<20 { vad.observe(rms: 0.035, time: Double(i) / 10) }
        XCTAssertFalse(vad.shouldEnd(now: 2.0, lastText: 1.8, silence: 1.2, hasText: true))
        XCTAssertFalse(vad.shouldEnd(now: 3.2, lastText: 3.0, silence: 1.2, hasText: true))
        XCTAssertTrue(vad.shouldEnd(now: 3.2, lastText: 2.0, silence: 1.2, hasText: true))
        XCTAssertFalse(vad.shouldEnd(now: 3.2, lastText: 2.0, silence: 1.2, hasText: false))
    }
}
