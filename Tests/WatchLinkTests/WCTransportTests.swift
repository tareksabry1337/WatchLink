import Testing
import Foundation
@testable import WatchLinkCore
@testable import WatchLink
import WatchLinkTestSupport

@Suite("WCTransport")
struct WCTransportTests {

    @Test("isReachable reflects session state")
    func reachability() async {
        let session = MockWCSession()
        let transport = WCTransport(session: session)

        session.isActivatedAndReachable = true
        let reachable = await transport.isReachable
        #expect(reachable == true)

        session.isActivatedAndReachable = false
        let unreachable = await transport.isReachable
        #expect(unreachable == false)
    }

    @Test("start activates the session")
    func startActivates() async {
        let session = MockWCSession()
        let transport = WCTransport(session: session)
        await transport.start()
        #expect(session.activateCalled)
    }

    @Test("send delivers data via session")
    func sendSuccess() async throws {
        let session = MockWCSession()
        let transport = WCTransport(session: session)
        let payload = Data("hello".utf8)
        try await transport.send(payload)
        #expect(session.sentData.count == 1)
        #expect(session.sentData.first == payload)
    }

    @Test("send queues data when unreachable")
    func sendQueuesWhenUnreachable() async {
        let session = MockWCSession()
        session.isActivatedAndReachable = false
        let transport = WCTransport(session: session)

        do {
            try await transport.send(Data("queued".utf8))
            Issue.record("Expected error")
        } catch {
            #expect(session.sentData.isEmpty)
        }
    }

    @Test("reachability change emits to stream")
    func reachabilityStream() async throws {
        let session = MockWCSession()
        let transport = WCTransport(session: session)
        let changes = await transport.reachabilityChanges

        await transport.handleReachabilityChanged(true)

        let value: Bool = try await firstValue(from: changes)
        #expect(value == true)
    }

    @Test("handleIncoming yields to stream")
    func incomingStream() async throws {
        let session = MockWCSession()
        let transport = WCTransport(session: session)
        let stream = await transport.incoming()

        let payload = Data("incoming".utf8)
        await transport.handleIncoming(payload)

        let received: IncomingMessage = try await withTimeout(.seconds(1)) {
            for await msg in stream { return msg }
            throw StreamEndedError()
        }

        #expect(received.data == payload)
    }

    @Test("stop finishes incoming stream")
    func stopFinishes() async {
        let session = MockWCSession()
        let transport = WCTransport(session: session)
        let stream = await transport.incoming()
        await transport.stop()

        var ended = false
        for await _ in stream {
            break
        }
        ended = true
        #expect(ended)
    }
}
