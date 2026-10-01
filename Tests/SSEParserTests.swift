import XCTest
@testable import ConversationTranslator

final class SSEParserTests: XCTestCase {
    func testWaitsForBoundaryAndPreservesMultipleDataLines() {
        var parser = SSEParser()
        XCTAssertNil(parser.consume(": heartbeat"))
        XCTAssertNil(parser.consume("event: message"))
        XCTAssertNil(parser.consume("data: first"))
        XCTAssertNil(parser.consume("data:second"))
        XCTAssertEqual(parser.consume(""), "first\nsecond")
        XCTAssertNil(parser.consume(""))
    }
    func testSeparateChunksAndDone() {
        var parser = SSEParser()
        XCTAssertNil(parser.consume("data: {\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}"))
        XCTAssertEqual(parser.consume(""), "{\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}")
        XCTAssertNil(parser.consume("data: [DONE]"))
        XCTAssertEqual(parser.consume(""), "[DONE]")
    }
}
