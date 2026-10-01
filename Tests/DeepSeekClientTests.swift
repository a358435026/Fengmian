import XCTest
@testable import ConversationTranslator

private final class TranslationURLProtocol: URLProtocol {
    static var status = 200
    static var body = ""
    static var capturedRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open(); defer { stream.close() }
            var body = Data(); var buffer = [UInt8](repeating: 0, count: 2048)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = body
        }
        Self.capturedRequest = captured
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Deliver every UTF-8 byte separately, including split Chinese code points.
        for byte in Self.body.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class DeepSeekClientTests: XCTestCase {
    private var session: URLSession!
    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranslationURLProtocol.self]
        session = URLSession(configuration: config)
        TranslationURLProtocol.status = 200
        TranslationURLProtocol.body = ""
        TranslationURLProtocol.capturedRequest = nil
    }
    override func tearDown() {
        session.invalidateAndCancel(); session = nil
        super.tearDown()
    }
    private func event(_ value: String) -> String { "data: \(value)\r\n\r\n" }
    private func translate(onDelta: @escaping @MainActor (String) -> Void) async throws {
        try await DeepSeekClient(session: session).translate(text: "Where is the station?",
                source: SpokenLanguage.all[1], target: SpokenLanguage.all[0], key: "test-only-key", context: "Earlier item: shipping quotation, smooth operation", onDelta: onDelta)
    }
    func testStreamedUnicodeAndOfficialEndpoint() async throws {
        TranslationURLProtocol.body = ": keepalive\r\n\r\n"
            + event("{\"choices\":[{\"delta\":{\"content\":\"车站\"},\"finish_reason\":null}]}")
            + event("{\"choices\":[{\"delta\":{\"content\":\"在哪里？\"},\"finish_reason\":null}]}")
            + event("{\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}")
            + event("[DONE]")
        var translation = ""
        try await translate { translation += $0 }
        XCTAssertEqual(translation, "车站在哪里？")
        let request = try XCTUnwrap(TranslationURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-key")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(payload["messages"] as? [[String: String]])
        XCTAssertTrue(messages[0]["content"]?.contains("negation") == true)
        XCTAssertTrue(messages[0]["content"]?.contains("shipping quotation") == true)
        XCTAssertEqual(messages.last?["content"], "Where is the station?")
    }
    func testIncompleteStreamIsRejected() async {
        TranslationURLProtocol.body = event("{\"choices\":[{\"delta\":{\"content\":\"车站\"},\"finish_reason\":null}]}")
        do { try await translate { _ in }; XCTFail("An incomplete translation must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("未完整")) }
    }
    func testAuthenticationFailureDoesNotEmitText() async {
        TranslationURLProtocol.status = 401
        TranslationURLProtocol.body = "unauthorized"
        var emitted = false
        do { try await translate { _ in emitted = true }; XCTFail("Invalid key must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("密钥")) }
        XCTAssertFalse(emitted)
    }
    func testTruncatedTranslationIsRejected() async {
        TranslationURLProtocol.body = event("{\"choices\":[{\"delta\":{\"content\":\"车站\"},\"finish_reason\":null}]}")
            + event("{\"choices\":[{\"delta\":{},\"finish_reason\":\"length\"}]}") + event("[DONE]")
        do { try await translate { _ in }; XCTFail("Truncated translation must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("长度")) }
    }
    func testEmptyKeyMakesNoRequest() async {
        do {
            try await DeepSeekClient(session: session).translate(text: "Hello", source: SpokenLanguage.all[1],
                        target: SpokenLanguage.all[0], key: "") { _ in XCTFail("No translation expected") }
            XCTFail("Empty key must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("密钥")) }
        XCTAssertNil(TranslationURLProtocol.capturedRequest)
    }
    func testRelayEndpointAndCustomModel() async throws {
        TranslationURLProtocol.body = event("{\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":\"stop\"}]}") + event("[DONE]")
        let config = APIConfiguration(provider: .custom, baseURL: "https://relay.example/v1/chat/completions", model: "custom-model", format: .openai)
        try await DeepSeekClient(session: session).translate(text: "你好", source: SpokenLanguage.all[0], target: SpokenLanguage.all[1], key: "test", configuration: config) { _ in }
        let request = try XCTUnwrap(TranslationURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, config.baseURL)
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "custom-model")
    }
    func testAnthropicNativeResponseAndHeaders() async throws {
        TranslationURLProtocol.body = "{\"content\":[{\"type\":\"text\",\"text\":\"Hello\"}],\"stop_reason\":\"end_turn\"}"
        var output = ""
        try await DeepSeekClient(session: session).translate(text: "你好", source: SpokenLanguage.all[0], target: SpokenLanguage.all[1], key: "test", configuration: .preset(.anthropic)) { output += $0 }
        XCTAssertEqual(output, "Hello")
        let request = try XCTUnwrap(TranslationURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
    func testGeminiNativeResponseAndHeaders() async throws {
        TranslationURLProtocol.body = "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"private thinking\",\"thought\":true},{\"text\":\"Hello\"}]},\"finishReason\":\"STOP\"}]}"
        var output = ""
        try await DeepSeekClient(session: session).translate(text: "你好", source: SpokenLanguage.all[0], target: SpokenLanguage.all[1], key: "test", configuration: .preset(.gemini)) { output += $0 }
        XCTAssertEqual(output, "Hello")
        let request = try XCTUnwrap(TranslationURLProtocol.capturedRequest)
        XCTAssertTrue(request.url!.path.hasSuffix(":generateContent"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test")
        XCTAssertNil(request.url?.query)
    }
    func testUnsafeAddressRejectedBeforeSendingCredential() async {
        let config = APIConfiguration(provider: .custom, baseURL: "http://relay.example/v1", model: "m", format: .openai)
        do {
            try await DeepSeekClient(session: session).translate(text: "你好", source: SpokenLanguage.all[0], target: SpokenLanguage.all[1], key: "test", configuration: config) { _ in }
            XCTFail("Unsafe address must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("HTTPS")) }
        XCTAssertNil(TranslationURLProtocol.capturedRequest)
    }

}
