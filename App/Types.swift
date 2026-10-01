import Foundation

struct SpokenLanguage: Identifiable, Hashable {
    let id: String
    let name: String
    let translationCode: String
    static let all: [Self] = [
        .init(id: "zh-CN", name: "中文（普通话）", translationCode: "zh-Hans"),
        .init(id: "en-US", name: "英语（美国）", translationCode: "en"),
        .init(id: "he-IL", name: "希伯来语", translationCode: "he"),
        .init(id: "ja-JP", name: "日语", translationCode: "ja"),
        .init(id: "ko-KR", name: "韩语", translationCode: "ko"),
        .init(id: "fr-FR", name: "法语", translationCode: "fr"),
        .init(id: "de-DE", name: "德语", translationCode: "de"),
        .init(id: "es-ES", name: "西班牙语", translationCode: "es"),
        .init(id: "pt-BR", name: "葡萄牙语（巴西）", translationCode: "pt"),
        .init(id: "it-IT", name: "意大利语", translationCode: "it"),
        .init(id: "ru-RU", name: "俄语", translationCode: "ru"),
        .init(id: "ar-SA", name: "阿拉伯语", translationCode: "ar"),
        .init(id: "hi-IN", name: "印地语", translationCode: "hi"),
        .init(id: "th-TH", name: "泰语", translationCode: "th"),
        .init(id: "vi-VN", name: "越南语", translationCode: "vi"),
        .init(id: "tr-TR", name: "土耳其语", translationCode: "tr"),
        .init(id: "id-ID", name: "印尼语", translationCode: "id")
    ]
}
struct Turn: Identifiable {
    let id: UUID
    let original: String
    let source: SpokenLanguage
    let target: SpokenLanguage
    var translation = ""
    var elapsed: Double?
    var firstToken: Double?
    var failed = false
}
struct OfflineJob: Identifiable {
    let id: UUID
    let text: String
    let source: SpokenLanguage
    let target: SpokenLanguage
    let prepareOnly: Bool
}
enum TranslatorError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

// SSE events may contain several data lines. Finish only on a blank line.
struct SSEParser {
    private var data: [String] = []
    mutating func consume(_ line: String) -> String? {
        if line.isEmpty {
            guard !data.isEmpty else { return nil }
            defer { data.removeAll() }
            return data.joined(separator: "\n")
        }
        guard line.hasPrefix("data:") else { return nil }
        var value = String(line.dropFirst(5))
        if value.hasPrefix(" ") { value.removeFirst() }
        data.append(value)
        return nil
    }
}
