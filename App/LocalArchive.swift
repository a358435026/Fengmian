import Foundation
import AVFoundation

enum LocalArchive {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Conversations", isDirectory: true)
    }
    static func temporaryAudio() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ConversationAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Only abandoned temporary files from earlier app launches exist before a new model starts.
        return directory.appendingPathComponent(UUID().uuidString + ".caf")
    }
    static func cleanupAbandonedAudio() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ConversationAudio", isDirectory: true)
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: file)
        }
    }
    static func list() -> [SavedConversation] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return folders.compactMap {
            guard let data = try? Data(contentsOf: $0.appendingPathComponent("transcript.json")) else { return nil }
            return try? decoder.decode(SavedConversation.self, from: data)
        }.sorted { $0.date > $1.date }
    }
    static func folder(_ conversation: SavedConversation) -> URL { directory.appendingPathComponent(conversation.id.uuidString, isDirectory: true) }
    static func files(_ conversation: SavedConversation) -> [URL] {
        ["audio.m4a", "transcript.txt", "transcript.json"].map { folder(conversation).appendingPathComponent($0) }
    }
    static func delete(_ conversation: SavedConversation) throws { try FileManager.default.removeItem(at: folder(conversation)) }
    static func save(audio: URL, conversation: SavedConversation) async throws {
        let output = folder(conversation)
        guard !FileManager.default.fileExists(atPath: output.path) else { throw TranslatorError.message("该对话已存在，未覆盖已有录音") }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        do {
            guard let export = AVAssetExportSession(asset: AVURLAsset(url: audio), presetName: AVAssetExportPresetAppleM4A) else {
                throw TranslatorError.message("系统无法导出录音")
            }
            export.outputURL = output.appendingPathComponent("audio.m4a")
            export.outputFileType = .m4a
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                export.exportAsynchronously { continuation.resume() }
            }
            guard export.status == .completed else { throw TranslatorError.message("录音保存失败，请检查可用空间后重试") }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(conversation).write(to: output.appendingPathComponent("transcript.json"), options: .atomic)
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            var lines = ["自由对话 · \(formatter.string(from: conversation.date))", "\(conversation.left.name) ↔ \(conversation.right.name)", ""]
            for turn in conversation.turns {
                lines.append(String(format: "[%02d:%02d] %@ → %@", Int(turn.startedAt) / 60, Int(turn.startedAt) % 60, turn.source.name, turn.target.name))
                if turn.needsConfirmation { lines.append("【识别待确认，以下内容不可当作已核对的译文】") }
                lines.append(turn.original)
                lines.append(turn.failed ? "【翻译未完成】" : turn.translation)
                for candidate in turn.alternatives where turn.needsConfirmation {
                    lines.append("候选 \(candidate.language.name)：\(candidate.text)")
                }
                lines.append("")
            }
            try lines.joined(separator: "\n").write(to: output.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: audio)
        } catch { try? FileManager.default.removeItem(at: output); throw error }
    }
}
