import XCTest
@testable import ConversationTranslator

private final class TranslationURLProtocol: URLProtocol {
    static var status = 200
    static var body = ""
    static var capturedRequest: URLRequest?
    static var capturedRequests: [URLRequest] = []
    static var contentType = "text/event-stream"
    static var responseHandler: ((URLRequest) -> (Int, String))?
    static var repeatKeepalives = false
    static var silentlyStall = false
    private var keepaliveTimer: DispatchSourceTimer?
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
        Self.capturedRequests.append(captured)
        let (status, body) = Self.responseHandler?(captured) ?? (Self.status, Self.body)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": Self.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if Self.silentlyStall { return }
        if Self.repeatKeepalives {
            let timer = DispatchSource.makeTimerSource(queue: .global())
            keepaliveTimer = timer
            timer.schedule(deadline: .now(), repeating: 0.02)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.client?.urlProtocol(self, didLoad: Data(": keepalive\n\n".utf8))
            }
            timer.resume()
            return
        }
        // Deliver every UTF-8 byte separately, including split Chinese code points.
        for byte in body.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { keepaliveTimer?.cancel(); keepaliveTimer = nil }
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
        TranslationURLProtocol.capturedRequests = []
        TranslationURLProtocol.responseHandler = nil
        TranslationURLProtocol.contentType = "text/event-stream"
        TranslationURLProtocol.repeatKeepalives = false
        TranslationURLProtocol.silentlyStall = false
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
        XCTAssertEqual(payload["model"] as? String, "deepseek-v4-pro")
        XCTAssertEqual((payload["thinking"] as? [String: String])?["type"], "disabled")
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
        XCTAssertNil(payload["thinking"], "Do not send provider-specific parameters to relays")
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

    func testDeepSeekModelDiscoveryPreservesExactIDsAndNames() async throws {
        TranslationURLProtocol.body = "{\"data\":[{\"id\":\"deepseek-flash\",\"name\":\"DeepSeek-V4.1-Flash\"},{\"id\":\"deepseek-v4-pro\",\"name\":\"DeepSeek-V4-Pro\"}]}"
        var config = APIConfiguration.preset(.deepseek)
        config.model = ""
        let models = try await DeepSeekClient(session: session).fetchModels(configuration: config, key: "test-key")
        XCTAssertEqual(models.map(\.id), ["deepseek-flash", "deepseek-v4-pro"])
        XCTAssertEqual(models.first?.name, "DeepSeek-V4.1-Flash")
        let request = try XCTUnwrap(TranslationURLProtocol.capturedRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertNil(request.httpBody)
    }

    func testModelDiscoveryStripsFullCompatibleEndpointAndTrimsID() async throws {
        TranslationURLProtocol.body = "{\"data\":[{\"id\":\"GPT-Custom-1\"}]}"
        let config = APIConfiguration(provider: .custom, baseURL: " https://relay.example/v1/chat/completions/ ", model: "  GPT-Custom-1  ", format: .openai)
        let models = try await DeepSeekClient(session: session).fetchModels(configuration: config, key: "test")
        XCTAssertEqual(models.first?.id, "GPT-Custom-1")
        XCTAssertEqual(TranslationURLProtocol.capturedRequest?.url?.absoluteString, "https://relay.example/v1/models")
        TranslationURLProtocol.body = event("{\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":\"stop\"}]}") + event("[DONE]")
        try await DeepSeekClient(session: session).translate(text: "你好", source: SpokenLanguage.all[0], target: SpokenLanguage.all[1], key: "test", configuration: config) { _ in }
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: TranslationURLProtocol.capturedRequest!.httpBody!) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "GPT-Custom-1")
    }

    func testAnthropicModelsFollowPaginationAndDeduplicate() async throws {
        TranslationURLProtocol.responseHandler = { request in
            if request.url?.query == nil {
                return (200, "{\"data\":[{\"id\":\"claude-first\",\"display_name\":\"Claude First\"}],\"has_more\":true,\"last_id\":\"claude-first\"}")
            }
            return (200, "{\"data\":[{\"id\":\"claude-first\"},{\"id\":\"claude-second\",\"display_name\":\"Claude Second\"}],\"has_more\":false}")
        }
        var config = APIConfiguration.preset(.anthropic)
        config.baseURL += "/messages"
        let models = try await DeepSeekClient(session: session).fetchModels(configuration: config, key: "native-key")
        XCTAssertEqual(models.map(\.id), ["claude-first", "claude-second"])
        XCTAssertEqual(TranslationURLProtocol.capturedRequests.count, 2)
        let request = try XCTUnwrap(TranslationURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/v1/models")
        XCTAssertEqual(request.url?.query, "after_id=claude-first")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "native-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testGeminiDiscoveryFiltersEmbeddingsAndFollowsToken() async throws {
        TranslationURLProtocol.responseHandler = { request in
            if request.url?.query == nil {
                return (200, "{\"models\":[{\"name\":\"models/text-embedding\",\"supportedGenerationMethods\":[\"embedContent\"]},{\"name\":\"models/gemini-Flash\",\"displayName\":\"Flash\",\"supportedGenerationMethods\":[\"generateContent\"]}],\"nextPageToken\":\"page-2\"}")
            }
            return (200, "{\"models\":[{\"name\":\"models/gemini-Pro\",\"supportedGenerationMethods\":[\"generateContent\"]}]}")
        }
        var config = APIConfiguration.preset(.gemini)
        config.baseURL += "/models/gemini-old:generateContent"
        let models = try await DeepSeekClient(session: session).fetchModels(configuration: config, key: "native-key")
        XCTAssertEqual(models.map(\.id), ["gemini-Flash", "gemini-Pro"])
        let request = try XCTUnwrap(TranslationURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.path, "/v1beta/models")
        XCTAssertEqual(request.url?.query, "pageToken=page-2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "native-key")
        XCTAssertFalse(request.url!.absoluteString.contains("native-key"))
    }

    func testOpenAIModelsPaginationStopsAtFivePages() async {
        var page = 0
        TranslationURLProtocol.responseHandler = { _ in
            page += 1
            return (200, "{\"data\":[{\"id\":\"model-\(page)\"}],\"has_more\":true}")
        }
        do {
            _ = try await DeepSeekClient(session: session).fetchModels(configuration: .preset(.openai), key: "test")
            XCTFail("Unbounded pagination must not succeed")
        } catch { XCTAssertTrue(error.localizedDescription.contains("分页")) }
        XCTAssertEqual(TranslationURLProtocol.capturedRequests.count, 5)
    }

    func testDiscoveryRejectsUnsafeAddressBeforeSendingKey() async {
        let config = APIConfiguration(provider: .custom, baseURL: "https://relay.example/v1?api_key=secret", model: "", format: .openai)
        do {
            _ = try await DeepSeekClient(session: session).fetchModels(configuration: config, key: "test")
            XCTFail("Credential URL must not be allowed")
        } catch { XCTAssertTrue(error.localizedDescription.contains("HTTPS")) }
        XCTAssertNil(TranslationURLProtocol.capturedRequest)
    }

    func testModelErrorHasActionableAdviceWithoutEchoingBody() async {
        TranslationURLProtocol.status = 400
        TranslationURLProtocol.body = "{\"error\":{\"type\":\"invalid_request_error\",\"message\":\"Model DeepSeek-Flash is invalid. Secret: test-only-key. User source: Where is the station?\"}}"
        do { try await translate { _ in }; XCTFail("Invalid model must fail") }
        catch {
            XCTAssertTrue(error.localizedDescription.contains("获取模型"))
            XCTAssertTrue(error.localizedDescription.contains("HTTP 400"))
            XCTAssertFalse(error.localizedDescription.contains("test-only-key"))
            XCTAssertFalse(error.localizedDescription.contains("Where is the station"))
            XCTAssertFalse(error.localizedDescription.contains("DeepSeek-Flash"))
        }
    }

    func testNativeProviderErrorIsSanitizedAndCategorized() async {
        TranslationURLProtocol.status = 403
        TranslationURLProtocol.body = "{\"error\":{\"status\":\"PERMISSION_DENIED\",\"message\":\"Key native-private-secret denied\"}}"
        do {
            try await DeepSeekClient(session: session).translate(text: "private-source", source: SpokenLanguage.all[0], target: SpokenLanguage.all[1], key: "native-private-secret", configuration: .preset(.gemini)) { _ in }
            XCTFail("No permission must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("权限"))
            XCTAssertFalse(error.localizedDescription.contains("native-private-secret"))
            XCTAssertFalse(error.localizedDescription.contains("private-source"))
        }
    }

    func testUnsupportedDiscoveryOffersManualModelFallback() async {
        TranslationURLProtocol.status = 404
        TranslationURLProtocol.body = "<html>Not found</html>"
        do {
            _ = try await DeepSeekClient(session: session).fetchModels(configuration: .preset(.openai), key: "test")
            XCTFail("Missing models endpoint must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("手动填写")) }
    }

    func testCompatibleNonstreamJSONCompletionIsAccepted() async throws {
        TranslationURLProtocol.contentType = "application/json; charset=utf-8"
        TranslationURLProtocol.body = "{\"choices\":[{\"message\":{\"content\":\"车站在哪里？\"},\"finish_reason\":\"stop\"}]}"
        var result = ""
        try await translate { result += $0 }
        XCTAssertEqual(result, "车站在哪里？")
    }

    func testCompatibleNonstreamTruncatedJSONIsRejected() async {
        TranslationURLProtocol.contentType = "application/json"
        TranslationURLProtocol.body = "{\"choices\":[{\"message\":{\"content\":\"partial\"},\"finish_reason\":\"length\"}]}"
        var emitted = false
        do { try await translate { _ in emitted = true }; XCTFail("Partial JSON must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("未完整")) }
        XCTAssertFalse(emitted)
    }

    func testWrongDisplayNameIsNotSilentlyReplaced() async throws {
        TranslationURLProtocol.body = event("{\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":\"stop\"}]}") + event("[DONE]")
        var config = APIConfiguration.preset(.deepseek)
        config.model = "DeepSeek-Flash"
        try await DeepSeekClient(session: session).translate(text: "你好", source: SpokenLanguage.all[0], target: SpokenLanguage.all[1], key: "test", configuration: config) { _ in }
        let body = try XCTUnwrap(TranslationURLProtocol.capturedRequest?.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "DeepSeek-Flash")
    }

    func testFilteredStreamNeverCountsAsSuccessfulTranslation() async {
        TranslationURLProtocol.body = event("{\"choices\":[{\"delta\":{\"content\":\"partial\"},\"finish_reason\":null}]}")
            + event("{\"choices\":[{\"delta\":{},\"finish_reason\":\"content_filter\"}]}") + event("[DONE]")
        do { try await translate { _ in }; XCTFail("Filtered output must not pass connection testing") }
        catch { XCTAssertTrue(error.localizedDescription.contains("未正常完成")) }
    }

    func testWhitespaceOnlyStreamIsRejected() async {
        TranslationURLProtocol.body = event("{\"choices\":[{\"delta\":{\"content\":\"   \\n\"},\"finish_reason\":\"stop\"}]}") + event("[DONE]")
        do { try await translate { _ in }; XCTFail("Whitespace must not pass connection testing") }
        catch { XCTAssertTrue(error.localizedDescription.contains("未完整")) }
    }

    func testKeepaliveStreamHasOverallDeadline() async {
        TranslationURLProtocol.repeatKeepalives = true
        let began = Date()
        do {
            try await DeepSeekClient(session: session, translationTimeout: 0.15).translate(text: "Hello", source: SpokenLanguage.all[1], target: SpokenLanguage.all[0], key: "test") { _ in }
            XCTFail("Keepalive-only stream must time out")
        } catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        XCTAssertLessThan(Date().timeIntervalSince(began), 5)
    }

    func testModelDiscoveryHasOverallDeadline() async {
        TranslationURLProtocol.repeatKeepalives = true
        do {
            _ = try await DeepSeekClient(session: session, modelDiscoveryTimeout: 0.15).fetchModels(configuration: .preset(.deepseek), key: "test")
            XCTFail("Unfinished model response must time out")
        } catch { XCTAssertTrue(error.localizedDescription.contains("获取模型超时")) }
    }

    func testSilentStreamIsCancelledByOverallDeadline() async {
        TranslationURLProtocol.silentlyStall = true
        let began = Date()
        do {
            try await DeepSeekClient(session: session, translationTimeout: 0.15).translate(text: "Hello", source: SpokenLanguage.all[1], target: SpokenLanguage.all[0], key: "test") { _ in }
            XCTFail("Silent stream must time out and cancel its request")
        } catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        XCTAssertLessThan(Date().timeIntervalSince(began), 5)
    }

}
