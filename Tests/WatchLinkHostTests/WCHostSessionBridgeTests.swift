#if os(iOS)
import Testing
import Foundation
import WatchConnectivity
@testable import WatchLinkCore
@testable import WatchLinkHost
import WatchLinkTestSupport

@Suite("WCHostSessionBridge")
struct WCHostSessionBridgeTests {

    @Test("activationDidComplete forwards reachability to transport")
    func activationForwards() async throws {
        let transport = WCHostTransport(session: MockWCSession())
        let bridge = WCHostSessionBridge(transport: transport, session: WCSession.default)
        let changes = await transport.reachabilityChanges

        bridge.session(WCSession.default, activationDidCompleteWith: .activated, error: nil)

        let value: Bool = try await firstValue(from: changes)
        #expect(value == WCSession.default.isReachable)
    }

    @Test("sessionReachabilityDidChange forwards to transport")
    func reachabilityForwards() async throws {
        let transport = WCHostTransport(session: MockWCSession())
        let bridge = WCHostSessionBridge(transport: transport, session: WCSession.default)
        let changes = await transport.reachabilityChanges

        bridge.sessionReachabilityDidChange(WCSession.default)

        let value: Bool = try await firstValue(from: changes)
        #expect(value == WCSession.default.isReachable)
    }

    @Test("didReceiveMessageData yields to transport incoming stream")
    func incomingNoReply() async throws {
        let transport = WCHostTransport(session: MockWCSession())
        let bridge = WCHostSessionBridge(transport: transport, session: WCSession.default)
        let stream = await transport.incoming()

        let payload = Data("from-watch".utf8)
        bridge.session(WCSession.default, didReceiveMessageData: payload)

        let received: IncomingMessage = try await withTimeout(.seconds(1)) {
            for await msg in stream { return msg }
            throw StreamEndedError()
        }
        #expect(received.data == payload)
    }

    @Test("didReceiveMessageData with replyHandler stores handler for later reply")
    func incomingWithReply() async throws {
        let transport = WCHostTransport(session: MockWCSession())
        let bridge = WCHostSessionBridge(transport: transport, session: WCSession.default)
        let stream = await transport.incoming()

        let frameData = try encodeFrame(PingMessage(count: 1))
        let frame = try JSONDecoder().decode(Frame.self, from: frameData)

        let replyHolder = AsyncHolder<Data>()
        bridge.session(WCSession.default, didReceiveMessageData: frameData) { replyData in
            Task { await replyHolder.send(replyData) }
        }

        _ = try await withTimeout(.seconds(1)) {
            for await _ in stream { return true }
            throw StreamEndedError()
        }

        let replyPayload = Data("pong".utf8)
        await transport.reply(to: frame.id, with: replyPayload)

        let forwardedReply: Data = try await withTimeout(.seconds(1)) {
            guard let value = await replyHolder.next() else { throw StreamEndedError() }
            return value
        }
        #expect(forwardedReply == replyPayload)
    }
}
#endif
