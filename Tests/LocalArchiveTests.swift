import XCTest
import AVFoundation
@testable import ConversationTranslator

@MainActor
final class LocalArchiveTests: XCTestCase {
    func testRecordingAndUncertainTranscriptsRoundTripLocally() async throws {
        let id = UUID()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString + ".caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3200))
        buffer.frameLength = 3200
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0..<3200 { channel[i] = 0.05 * sin(Float(i) * 0.17) }
        do { let file = try AVAudioFile(forWriting: temporary, settings: format.settings); try file.write(from: buffer) }
        var turn = Turn(id: UUID(), original: "Do not ship before Friday", source: SpokenLanguage.all[1], target: SpokenLanguage.all[0])
        turn.needsConfirmation = true; turn.pending = false
        turn.alternatives = [.init(language: turn.source, text: turn.original, confidence: 0.4)]
        let record = SavedConversation(id: id, date: Date(), duration: 0.2, left: turn.target, right: turn.source, turns: [turn], audioFile: "audio.m4a")
        defer { try? LocalArchive.delete(record); try? FileManager.default.removeItem(at: temporary) }
        try await LocalArchive.save(audio: temporary, conversation: record)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        for file in LocalArchive.files(record) { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path)) }
        let restored = try XCTUnwrap(LocalArchive.list().first { $0.id == id })
        XCTAssertEqual(restored.turns[0].original, turn.original)
        XCTAssertTrue(restored.turns[0].needsConfirmation)
        let text = try String(contentsOf: LocalArchive.folder(record).appendingPathComponent("transcript.txt"), encoding: .utf8)
        XCTAssertTrue(text.contains("识别待确认"))
        XCTAssertTrue(text.contains("Do not ship before Friday"))
        let audio = try AVAudioPlayer(contentsOf: LocalArchive.folder(record).appendingPathComponent("audio.m4a"))
        XCTAssertGreaterThan(audio.duration, 0)
    }
    func testSaveDoesNotOverwriteExistingRecording() async throws {
        let record = SavedConversation(id: UUID(), date: Date(), duration: 0, left: SpokenLanguage.all[0], right: SpokenLanguage.all[1], turns: [], audioFile: "audio.m4a")
        let folder = LocalArchive.folder(record)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let marker = folder.appendingPathComponent("keep.txt")
        try "existing recording".write(to: marker, atomically: true, encoding: .utf8)
        defer { try? LocalArchive.delete(record) }
        do {
            try await LocalArchive.save(audio: folder.appendingPathComponent("missing.caf"), conversation: record)
            XCTFail("Should not overwrite an existing conversation")
        } catch { XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path)) }
    }
}
