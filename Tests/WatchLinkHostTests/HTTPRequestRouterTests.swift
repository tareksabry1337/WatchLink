#if os(iOS)
import Testing
import Foundation
@testable import WatchLinkCore
@testable import WatchLinkHost
import WatchLinkTestSupport

@Suite("HTTPRequestRouter")
struct HTTPRequestRouterTests {

    private func parse(_ raw: String) -> HTTPRequestRouter.ParsedRequest {
        HTTPRequestRouter.parse(Data(raw.utf8))
    }

    // MARK: - Parsing

    @Test("parses HEAD /health")
    func parseHealth() {
        let parsed = parse("HEAD /health HTTP/1.1\r\nHost: x\r\n\r\n")
        #expect(parsed.route == .health)
        #expect(parsed.body == nil)
    }

    @Test("parses POST /message with body")
    func parseMessage() {
        let parsed = parse("POST /message HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello")
        #expect(parsed.route == .message)
        #expect(parsed.body == Data("hello".utf8))
    }

    @Test("parses POST /reply with x-frame-id header")
    func parseReplyWithHeader() {
        let parsed = parse("POST /reply HTTP/1.1\r\nX-Frame-ID: abc123\r\nContent-Length: 4\r\n\r\ndata")
        #expect(parsed.route == .reply)
        #expect(parsed.headers["x-frame-id"] == "abc123")
        #expect(parsed.body == Data("data".utf8))
    }

    @Test("parses GET /events")
    func parseEvents() {
        let parsed = parse("GET /events HTTP/1.1\r\n\r\n")
        #expect(parsed.route == .events)
    }

    @Test("unknown path yields nil route")
    func parseUnknown() {
        let parsed = parse("GET /not-a-route HTTP/1.1\r\n\r\n")
        #expect(parsed.route == nil)
    }

    @Test("wrong method for path yields nil route")
    func parseWrongMethod() {
        let parsed = parse("GET /message HTTP/1.1\r\n\r\n")
        #expect(parsed.route == nil)
    }

    @Test("header keys are lowercased")
    func parseHeaderCase() {
        let parsed = parse("HEAD /health HTTP/1.1\r\nContent-TYPE: text/plain\r\nAccept: */*\r\n\r\n")
        #expect(parsed.headers["content-type"] == "text/plain")
        #expect(parsed.headers["accept"] == "*/*")
    }

    @Test("body absent when no \\r\\n\\r\\n separator")
    func parseNoSeparator() {
        let parsed = parse("POST /message HTTP/1.1\r\nContent-Length: 5")
        #expect(parsed.body == nil)
    }

    @Test("empty body treated as nil")
    func parseEmptyBody() {
        let parsed = parse("POST /message HTTP/1.1\r\nContent-Length: 0\r\n\r\n")
        #expect(parsed.body == nil)
    }

    // MARK: - parseContentLength

    @Test("parseContentLength extracts numeric value")
    func contentLengthNumeric() {
        #expect(HTTPRequestRouter.parseContentLength("POST /x HTTP/1.1\r\nContent-Length: 42\r\n\r\n") == 42)
    }

    @Test("parseContentLength returns 0 when header missing")
    func contentLengthMissing() {
        #expect(HTTPRequestRouter.parseContentLength("POST /x HTTP/1.1\r\n\r\n") == 0)
    }

    @Test("parseContentLength is case-insensitive")
    func contentLengthCaseInsensitive() {
        #expect(HTTPRequestRouter.parseContentLength("POST /x HTTP/1.1\r\nCONTENT-LENGTH: 99\r\n\r\n") == 99)
    }

    @Test("parseContentLength returns 0 for malformed value")
    func contentLengthMalformed() {
        #expect(HTTPRequestRouter.parseContentLength("POST /x HTTP/1.1\r\nContent-Length: abc\r\n\r\n") == 0)
    }

    // MARK: - effects(for:)

    @Test("/health → respond 200")
    func effectsHealth() {
        let parsed = parse("HEAD /health HTTP/1.1\r\n\r\n")
        #expect(HTTPRequestRouter.effects(for: parsed) == [.respond(.ok, body: nil)])
    }

    @Test("/message with body → yield incoming then respond 200")
    func effectsMessageWithBody() {
        let parsed = parse("POST /message HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello")
        #expect(HTTPRequestRouter.effects(for: parsed) == [
            .yieldIncoming(Data("hello".utf8)),
            .respond(.ok, body: nil),
        ])
    }

    @Test("/message with empty body → respond 200 only")
    func effectsMessageNoBody() {
        let parsed = parse("POST /message HTTP/1.1\r\nContent-Length: 0\r\n\r\n")
        #expect(HTTPRequestRouter.effects(for: parsed) == [.respond(.ok, body: nil)])
    }

    @Test("/request with valid Frame body → yield incoming + hold for reply")
    func effectsRequestValidFrame() throws {
        let frameData = try encodeFrame(AskMessage(question: "q"))
        let frame = try JSONDecoder().decode(Frame.self, from: frameData)
        let bodyString = String(data: frameData, encoding: .utf8)!
        let raw = "POST /request HTTP/1.1\r\nContent-Length: \(bodyString.utf8.count)\r\n\r\n\(bodyString)"
        let parsed = parse(raw)
        #expect(HTTPRequestRouter.effects(for: parsed) == [
            .yieldIncoming(frameData),
            .holdConnection(frameID: frame.id),
        ])
    }

    @Test("/request without body → respond 404")
    func effectsRequestNoBody() {
        let parsed = parse("POST /request HTTP/1.1\r\nContent-Length: 0\r\n\r\n")
        #expect(HTTPRequestRouter.effects(for: parsed) == [.respond(.notFound, body: nil)])
    }

    @Test("/request with non-Frame body → respond 404")
    func effectsRequestBadBody() {
        let parsed = parse("POST /request HTTP/1.1\r\nContent-Length: 7\r\n\r\ngarbage")
        #expect(HTTPRequestRouter.effects(for: parsed) == [.respond(.notFound, body: nil)])
    }

    @Test("/reply with frameID and body → resolve + respond 200")
    func effectsReplyFull() {
        let parsed = parse("POST /reply HTTP/1.1\r\nX-Frame-ID: abc\r\nContent-Length: 4\r\n\r\ndata")
        #expect(HTTPRequestRouter.effects(for: parsed) == [
            .resolveReply(frameID: "abc", Data("data".utf8)),
            .respond(.ok, body: nil),
        ])
    }

    @Test("/reply missing frameID → respond 200 only")
    func effectsReplyNoFrameID() {
        let parsed = parse("POST /reply HTTP/1.1\r\nContent-Length: 4\r\n\r\ndata")
        #expect(HTTPRequestRouter.effects(for: parsed) == [.respond(.ok, body: nil)])
    }

    @Test("/reply missing body → respond 200 only")
    func effectsReplyNoBody() {
        let parsed = parse("POST /reply HTTP/1.1\r\nX-Frame-ID: abc\r\nContent-Length: 0\r\n\r\n")
        #expect(HTTPRequestRouter.effects(for: parsed) == [.respond(.ok, body: nil)])
    }

    @Test("/events → startSSE")
    func effectsEvents() {
        let parsed = parse("GET /events HTTP/1.1\r\n\r\n")
        #expect(HTTPRequestRouter.effects(for: parsed) == [.startSSE])
    }

    @Test("unknown path → respond 404")
    func effectsUnknown() {
        let parsed = parse("GET /nope HTTP/1.1\r\n\r\n")
        #expect(HTTPRequestRouter.effects(for: parsed) == [.respond(.notFound, body: nil)])
    }
}
#endif
