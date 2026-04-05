import Testing
import Foundation
@testable import WatchLinkCore

@Suite("ControlFrame")
struct ControlFrameTests {
    @Test("ping round-trip")
    func pingRoundTrip() throws {
        let data = try JSONEncoder().encode(ControlFrame.ping)
        let decoded = try JSONDecoder().decode(ControlFrame.self, from: data)
        if case .ping = decoded {} else {
            Issue.record("Expected .ping")
        }
    }

    @Test("pong round-trip")
    func pongRoundTrip() throws {
        let data = try JSONEncoder().encode(ControlFrame.pong)
        let decoded = try JSONDecoder().decode(ControlFrame.self, from: data)
        if case .pong = decoded {} else {
            Issue.record("Expected .pong")
        }
    }
}
