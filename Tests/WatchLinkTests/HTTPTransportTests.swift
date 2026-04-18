import Testing
import Foundation
@testable import WatchLinkCore
@testable import WatchLink
import WatchLinkTestSupport

@Suite("HTTPTransport")
struct HTTPTransportTests {

    @Test("not reachable initially")
    func initiallyUnreachable() async {
        let transport = HTTPTransport(port: 8188)
        let reachable = await transport.isReachable
        #expect(reachable == false)
    }

    @Test("reachable after IP is set")
    func reachableAfterIP() async {
        let transport = HTTPTransport(port: 8188)
        await transport.updateServerIP("192.168.1.1")
        let reachable = await transport.isReachable
        #expect(reachable == true)
    }

    @Test("unreachable after IP is cleared")
    func unreachableAfterClear() async {
        let transport = HTTPTransport(port: 8188)
        await transport.updateServerIP("192.168.1.1")
        await transport.clearServerIP()
        let reachable = await transport.isReachable
        #expect(reachable == false)
    }

    @Test("send fails without server IP")
    func sendWithoutIP() async {
        let transport = HTTPTransport(port: 8188)

        do {
            try await transport.send(Data("test".utf8))
            Issue.record("Expected error")
        } catch {
            #expect(error is WatchLinkError)
        }
    }

    @Test("send makes POST to /message")
    func sendPostsToMessage() async throws {
        let mockSession = MockURLSession()
        let transport = HTTPTransport(port: 8188, urlSession: mockSession)
        await transport.updateServerIP("192.168.1.1")

        let payload = Data("test".utf8)
        try await transport.send(payload)

        #expect(mockSession.receivedRequests.count == 1)
        let request = mockSession.receivedRequests[0]
        #expect(request.url?.path == HTTPRoute.message.path)
        #expect(request.httpMethod == HTTPRoute.message.method.rawValue)
        #expect(request.httpBody == payload)
    }

    @Test("send throws on non-200 response")
    func sendThrowsOnBadStatus() async {
        let mockSession = MockURLSession()
        mockSession.responseCode = 500
        let transport = HTTPTransport(port: 8188, urlSession: mockSession)
        await transport.updateServerIP("192.168.1.1")

        do {
            try await transport.send(Data("test".utf8))
            Issue.record("Expected error")
        } catch {
            #expect(error is WatchLinkError)
        }
    }

    @Test("send throws on network failure")
    func sendThrowsOnFailure() async {
        let mockSession = MockURLSession()
        mockSession.shouldFail = true
        let transport = HTTPTransport(port: 8188, urlSession: mockSession)
        await transport.updateServerIP("192.168.1.1")

        do {
            try await transport.send(Data("test".utf8))
            Issue.record("Expected error")
        } catch {
            #expect(error is WatchLinkError)
        }
    }

    @Test("stop resets reachability")
    func stopResetsReachability() async {
        let transport = HTTPTransport(port: 8188)
        await transport.updateServerIP("192.168.1.1")
        await transport.stop()
        let reachable = await transport.isReachable
        #expect(reachable == false)
    }

    @Test("constructs correct URL from IP and port")
    func correctURL() async throws {
        let mockSession = MockURLSession()
        let transport = HTTPTransport(port: 9999, urlSession: mockSession)
        await transport.updateServerIP("10.0.0.5")

        try await transport.send(Data())

        let url = mockSession.receivedRequests.first?.url
        #expect(url?.host == "10.0.0.5")
        #expect(url?.port == 9999)
    }

    @Test("clearServerIP resets reachability")
    func clearResetsReachability() async {
        let transport = HTTPTransport(port: 8188)
        await transport.updateServerIP("1.2.3.4")
        await transport.clearServerIP()
        let reachable = await transport.isReachable
        #expect(reachable == false)
    }

    @Test("reachability stream emits true when IP is set")
    func reachabilityEmitsOnIPSet() async throws {
        let transport = HTTPTransport(port: 8188)
        let changes = await transport.reachabilityChanges
        await transport.updateServerIP("192.168.1.1")

        let value: Bool = try await firstValue(from: changes)
        #expect(value == true)
    }

    @Test("reachability stream emits false when IP is cleared")
    func reachabilityEmitsOnIPClear() async throws {
        let transport = HTTPTransport(port: 8188)
        let changes = await transport.reachabilityChanges

        await transport.updateServerIP("192.168.1.1")
        await transport.clearServerIP()

        let collector = AsyncCollector<Bool>()
        let collected: [Bool] = try await withTimeout(.seconds(10)) {
            for await value in changes {
                await collector.append(value)
                if await collector.values.count >= 2 { break }
            }
            return await collector.values
        }

        #expect(collected.contains(true))
        #expect(collected.contains(false))
    }




    @Test("stop finishes reachability stream")
    func stopFinishesReachability() async {
        let transport = HTTPTransport(port: 8188)
        let changes = await transport.reachabilityChanges
        await transport.stop()

        var ended = true
        for await _ in changes {
            ended = false
            break
        }
        #expect(ended)
    }
}
