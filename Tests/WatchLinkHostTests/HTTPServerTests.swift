#if os(iOS)
import Testing
import Foundation
@testable import WatchLinkCore
@testable import WatchLinkHost
import WatchLinkTestSupport

@Suite("HTTPServer")
struct HTTPServerTests {

    private func startServer() async throws -> HTTPServer {
        let server = HTTPServer(port: 0, heartbeatInterval: .seconds(600))
        let reachable = await server.reachabilityChanges
        await server.start()
        _ = try await firstValue(from: reachable, timeout: .seconds(2))
        return server
    }

    @Test("start binds listener and exposes boundPort")
    func startBinds() async throws {
        let server = try await startServer()
        let port = try #require(await server.boundPort)
        #expect(port > 0)
        await server.stop()
    }

    @Test("pause clears listener and reachability")
    func pauseClears() async throws {
        let server = try await startServer()
        await server.pause()
        let reachable = await server.isReachable
        let port = await server.boundPort
        #expect(reachable == false)
        #expect(port == nil)
        await server.stop()
    }

    @Test("stop finishes reachability stream")
    func stopFinishesReachability() async {
        let server = HTTPServer(port: 0)
        let changes = await server.reachabilityChanges
        await server.stop()

        var ended = true
        for await _ in changes {
            ended = false
            break
        }
        #expect(ended)
    }

    @Test("stop finishes incoming stream")
    func stopFinishesIncoming() async {
        let server = HTTPServer(port: 0)
        let stream = await server.incoming()
        await server.stop()

        var ended = true
        for await _ in stream {
            ended = false
            break
        }
        #expect(ended)
    }

}
#endif
