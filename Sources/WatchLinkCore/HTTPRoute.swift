package enum HTTPRoute: Sendable, Equatable {
    case message
    case events
    case health

    package var path: String {
        switch self {
        case .message: "/message"
        case .events: "/events"
        case .health: "/health"
        }
    }

    package var method: HTTPMethod {
        switch self {
        case .message: .post
        case .events: .get
        case .health: .head
        }
    }

    package init?(method: HTTPMethod, path: String) {
        switch (method, path) {
        case (.post, "/message"): self = .message
        case (.get, "/events"): self = .events
        case (.head, "/health"): self = .health
        default: return nil
        }
    }
}
