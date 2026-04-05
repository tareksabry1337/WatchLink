import Testing
@testable import WatchLinkCore

@Suite("ConnectionState")
struct ConnectionStateTests {
    @Test("equality — same states")
    func equality() {
        #expect(ConnectionState.disconnected == .disconnected)
        #expect(ConnectionState.connecting == .connecting)
        #expect(ConnectionState.connected == .connected)
        #expect(ConnectionState.reconnecting(attempt: 2) == .reconnecting(attempt: 2))
    }

    @Test("inequality — different states")
    func inequality() {
        #expect(ConnectionState.disconnected != .connected)
        #expect(ConnectionState.reconnecting(attempt: 1) != .reconnecting(attempt: 2))
    }

    @Test("description — disconnected")
    func descriptionDisconnected() {
        #expect(ConnectionState.disconnected.description == "disconnected")
    }

    @Test("description — connecting")
    func descriptionConnecting() {
        #expect(ConnectionState.connecting.description == "connecting")
    }

    @Test("description — connected")
    func descriptionConnected() {
        #expect(ConnectionState.connected.description == "connected")
    }

    @Test("description — reconnecting includes attempt")
    func descriptionReconnecting() {
        #expect(ConnectionState.reconnecting(attempt: 3).description == "reconnecting (attempt 3)")
    }
}
