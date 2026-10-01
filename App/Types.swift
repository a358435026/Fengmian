import Foundation

struct SpokenLanguage: Identifiable, Hashable, Codable {
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
struct Turn: Identifiable, Codable {
    let id: UUID
    var original: String
    var source: SpokenLanguage
    var target: SpokenLanguage
    var translation = ""
    var elapsed: Double?
    var firstToken: Double?
    var failed = false
    var pending = true
    var needsConfirmation = false
    var alternatives: [CandidateRecord] = []
    var startedAt: Double = 0
    var endedAt: Double = 0
    var recognitionNote: String?
}
struct CandidateRecord: Codable, Identifiable {
    var id: String { language.id }
    let language: SpokenLanguage
    let text: String
    let confidence: Double
}
struct SavedConversation: Codable, Identifiable {
    let id: UUID
    let date: Date
    let duration: Double
    let left: SpokenLanguage
    let right: SpokenLanguage
    let turns: [Turn]
    let audioFile: String
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

// Non-secret configuration. Credentials stay in Keychain, separated by service.
enum APIProvider: String, CaseIterable, Codable, Identifiable {
    case deepseek, openai, anthropic, gemini, qwen, moonshot, glm, custom
    var id: String { rawValue }
    var name: String {
        switch self {
        case .deepseek: return "DeepSeek 官方"
        case .openai: return "OpenAI 官方"
        case .anthropic: return "Anthropic Claude 官方"
        case .gemini: return "Google Gemini 官方"
        case .qwen: return "阿里通义千问"
        case .moonshot: return "Moonshot / Kimi"
        case .glm: return "智谱 GLM"
        case .custom: return "自定义 / 第三方中转"
        }
    }
    var endpoint: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .moonshot: return "https://api.moonshot.cn/v1"
        case .glm: return "https://open.bigmodel.cn/api/paas/v4"
        case .custom: return ""
        }
    }
    var model: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .openai: return "gpt-4.1-mini"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .gemini: return "gemini-2.5-flash"
        case .qwen: return "qwen-turbo"
        case .moonshot: return "moonshot-v1-8k"
        case .glm: return "glm-4-flash"
        case .custom: return ""
        }
    }
}
enum APIWireFormat: String, CaseIterable, Codable, Identifiable {
    case openai, anthropic, gemini
    var id: String { rawValue }
    var name: String { switch self { case .openai: return "OpenAI 兼容"; case .anthropic: return "Anthropic Messages"; case .gemini: return "Gemini 原生" } }
}
struct APIConfiguration: Codable, Equatable {
    var provider: APIProvider = .deepseek
    var baseURL = APIProvider.deepseek.endpoint
    var model = APIProvider.deepseek.model
    var format: APIWireFormat = .openai
    static func preset(_ provider: APIProvider) -> Self {
        .init(provider: provider, baseURL: provider.endpoint, model: provider.model,
              format: provider == .anthropic ? .anthropic : provider == .gemini ? .gemini : .openai)
    }
    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "translationAPIConfiguration"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
    func save() throws {
        _ = try requestURL()
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: "translationAPIConfiguration")
    }
    func requestURL() throws -> URL {
        let clean = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let base = URLComponents(string: clean), base.scheme == "https", base.host != nil,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else {
            throw TranslatorError.message("API 地址需为 HTTPS，不能包含密钥、查询参数或用户名")
        }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw TranslatorError.message("请填写模型名称") }
        let endpoint: String
        switch format {
        case .openai: endpoint = clean.hasSuffix("/chat/completions") ? clean : clean + "/chat/completions"
        case .anthropic: endpoint = clean.hasSuffix("/messages") ? clean : clean + "/messages"
        case .gemini:
            guard !model.contains("/"), !model.contains(":"), !model.contains("?"), !model.contains("#") else {
                throw TranslatorError.message("Gemini 模型名称只填模型 ID，不填 URL")
            }
            endpoint = clean + "/models/" + model + ":generateContent"
        }
        guard let url = URL(string: endpoint) else { throw TranslatorError.message("API 地址无效") }
        return url
    }
}
