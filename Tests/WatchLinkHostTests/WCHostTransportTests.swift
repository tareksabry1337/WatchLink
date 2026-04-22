#if os(iOS)
import Testing
import Foundation
@testable import WatchLinkCore
@testable import WatchLinkHost
import WatchLinkTestSupport

@Suite("WCHostTransport")
struct WCHostTransportTests {

    @Test("isReachable reflects session state")
    func reachability() async {
        let session = MockWCSession()
        let transport = WCHostTransport(session: session)

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
        let transport = WCHostTransport(session: session)
        await transport.start()
        #expect(session.activateCalled)
    }

    @Test("send delivers data via session")
    func sendSuccess() async throws {
        let session = MockWCSession()
        let transport = WCHostTransport(session: session)
        let payload = Data("hello".utf8)
        try await transport.send(payload)
        #expect(session.sentData.count == 1)
        #expect(session.sentData.first == payload)
    }

    @Test("send fails when unreachable")
    func sendFailsWhenUnreachable() async {
        let session = MockWCSession()
        session.isActivatedAndReachable = false
        let transport = WCHostTransport(session: session)

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
        let transport = WCHostTransport(session: session)
        let changes = await transport.reachabilityChanges

        await transport.handleReachabilityChanged(true)

        let value: Bool = try await firstValue(from: changes)
        #expect(value == true)
    }

    @Test("handleIncoming yields to stream")
    func incomingStream() async throws {
        let session = MockWCSession()
        let transport = WCHostTransport(session: session)
        let stream = await transport.incoming()

        let payload = Data("incoming".utf8)
        await transport.handleIncoming(payload)

        let received: IncomingMessage = try await withTimeout(.seconds(30)) {
            for await msg in stream { return msg }
            throw StreamEndedError()
        }

        #expect(received.data == payload)
    }

    @Test("stop finishes incoming stream")
    func stopFinishes() async {
        let session = MockWCSession()
        let transport = WCHostTransport(session: session)
        let stream = await transport.incoming()
        await transport.stop()

        var ended = false
        for await _ in stream {
            break
        }
        ended = true
        #expect(ended)
    }

    @Test("request returns data from session reply handler")
    func requestReturnsReply() async throws {
        let session = MockWCSession()
        let replyPayload = Data("pong".utf8)
        session.replyData = replyPayload
        let transport = WCHostTransport(session: session)

        let result = try await transport.request(Data("ping".utf8))
        #expect(result == replyPayload)
        #expect(session.sentData.first == Data("ping".utf8))
    }

    @Test("request throws when session is unreachable")
    func requestFailsWhenUnreachable() async {
        let session = MockWCSession()
        session.isActivatedAndReachable = false
        let transport = WCHostTransport(session: session)

        do {
            _ = try await transport.request(Data("ping".utf8))
            Issue.record("Expected error")
        } catch {
            #expect(error is WatchLinkError)
            #expect(session.sentData.isEmpty)
        }
    }

    @Test("request propagates session error")
    func requestPropagatesError() async {
        let session = MockWCSession()
        session.replyError = WatchLinkError.sendFailed("WC failed")
        let transport = WCHostTransport(session: session)

        do {
            _ = try await transport.request(Data("ping".utf8))
            Issue.record("Expected error")
        } catch let error as WatchLinkError {
            if case .sendFailed = error { /* ok */ } else { Issue.record("Wrong error case") }
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test("populateDiagnostics writes wcReachable flag")
    func populateDiagnostics() async {
        let session = MockWCSession()
        session.isActivatedAndReachable = true
        let transport = WCHostTransport(session: session)

        var diagnostics = WatchLinkDiagnostics()
        await transport.populateDiagnostics(&diagnostics)
        #expect(diagnostics.wcReachable == true)

        session.isActivatedAndReachable = false
        var diagnostics2 = WatchLinkDiagnostics()
        await transport.populateDiagnostics(&diagnostics2)
        #expect(diagnostics2.wcReachable == false)
    }

    @Test("handleIncoming with reply handler invokes handler on reply")
    func replyHandlerInvoked() async throws {
        let session = MockWCSession()
        let transport = WCHostTransport(session: session)

        let frameData = try encodeFrame(PingMessage(count: 1))
        let frame = try JSONDecoder().decode(Frame.self, from: frameData)

        let holder = AsyncHolder<Data>()
        await transport.handleIncoming(frameData, wcReplyHandler: { data in
            Task { await holder.send(data) }
        })

        let replyPayload = Data("pong".utf8)
        await transport.reply(to: frame.id, with: replyPayload)

        let received: Data = try await withTimeout(.seconds(30)) {
            guard let value = await holder.next() else { throw StreamEndedError() }
            return value
        }
        #expect(received == replyPayload)
    }

}
#endif
