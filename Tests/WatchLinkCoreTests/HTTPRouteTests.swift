import Testing
@testable import WatchLinkCore

@Suite("HTTPRoute")
struct HTTPRouteTests {
    @Test("message route properties")
    func messageRoute() {
        #expect(HTTPRoute.message.path == "/message")
        #expect(HTTPRoute.message.method == .post)
    }

    @Test("events route properties")
    func eventsRoute() {
        #expect(HTTPRoute.events.path == "/events")
        #expect(HTTPRoute.events.method == .get)
    }

    @Test("health route properties")
    func healthRoute() {
        #expect(HTTPRoute.health.path == "/health")
        #expect(HTTPRoute.health.method == .head)
    }

    @Test("init from POST /message")
    func initMessage() {
        let route = HTTPRoute(method: .post, path: "/message")
        #expect(route == .message)
    }

    @Test("init from GET /events")
    func initEvents() {
        let route = HTTPRoute(method: .get, path: "/events")
        #expect(route == .events)
    }

    @Test("init from HEAD /health matches health")
    func initHealth() {
        let route = HTTPRoute(method: .head, path: "/health")
        #expect(route == .health)
    }

    @Test("init from HEAD on unknown path returns nil")
    func initHeadUnknown() {
        let route = HTTPRoute(method: .head, path: "/anything")
        #expect(route == nil)
    }

    @Test("init returns nil for unknown route")
    func initUnknown() {
        let route = HTTPRoute(method: .get, path: "/unknown")
        #expect(route == nil)
    }

    @Test("init returns nil for wrong method on known path")
    func initWrongMethod() {
        let route = HTTPRoute(method: .get, path: "/message")
        #expect(route == nil)
    }
}
