import Testing
import Foundation
@testable import WatchLinkCore
import WatchLinkTestSupport

@Suite("Frame")
struct FrameTests {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    @Test("message frame has correct kind and channel")
    func messageFrame() throws {
        let frame = try Frame(wrapping: PingMessage(count: 1), encoder: encoder)
        #expect(frame.kind == .message)
        #expect(frame.channel == PingMessage.channel)
    }

    @Test("control frame has correct kind and nil channel")
    func controlFrame() throws {
        let frame = try Frame(control: .ping, encoder: encoder)
        #expect(frame.kind == .control)
        #expect(frame.channel == nil)
    }

    @Test("message frame generates unique IDs")
    func uniqueIDs() throws {
        let f1 = try Frame(wrapping: PingMessage(count: 1), encoder: encoder)
        let f2 = try Frame(wrapping: PingMessage(count: 2), encoder: encoder)
        #expect(f1.id != f2.id)
    }

    @Test("message payload decodes back to original")
    func payloadRoundTrip() throws {
        let frame = try Frame(wrapping: PingMessage(count: 42), encoder: encoder)
        let decoded = try decoder.decode(PingMessage.self, from: frame.payload)
        #expect(decoded.count == 42)
    }

    @Test("control payload decodes back to control frame")
    func controlPayloadRoundTrip() throws {
        let frame = try Frame(control: .pong, encoder: encoder)
        let decoded = try decoder.decode(ControlFrame.self, from: frame.payload)
        if case .pong = decoded {} else {
            Issue.record("Expected pong")
        }
    }

    @Test("full codable round-trip for message frame")
    func messageRoundTrip() throws {
        let original = try Frame(wrapping: PongMessage(count: 7), encoder: encoder)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Frame.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.kind == .message)
        #expect(decoded.channel == PongMessage.channel)
    }

    @Test("full codable round-trip for control frame")
    func controlRoundTrip() throws {
        let original = try Frame(control: .pong, encoder: encoder)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Frame.self, from: data)
        #expect(decoded.kind == .control)
        #expect(decoded.channel == nil)
    }

    @Test("only one level of encoding — no nested base64")
    func noNestedBase64() throws {
        let frame = try Frame(wrapping: PingMessage(count: 1), encoder: encoder)
        let wireData = try encoder.encode(frame)
        let json = String(data: wireData, encoding: .utf8)!
        let base64Count = json.components(separatedBy: "\"payload\":\"").count - 1
        #expect(base64Count == 1)
    }
}
