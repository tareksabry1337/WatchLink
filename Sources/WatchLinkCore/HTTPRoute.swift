package enum HTTPRoute: Sendable, Equatable {
    case message
    case request
    case reply
    case events
    case health

    package var path: String {
        switch self {
        case .message: "/message"
        case .request: "/request"
        case .reply: "/reply"
        case .events: "/events"
        case .health: "/health"
        }
    }

    package var method: HTTPMethod {
        switch self {
        case .message: .post
        case .request: .post
        case .reply: .post
        case .events: .get
        case .health: .head
        }
    }

    package init?(method: HTTPMethod, path: String) {
        switch (method, path) {
        case (.post, "/message"): self = .message
        case (.post, "/request"): self = .request
        case (.post, "/reply"): self = .reply
        case (.get, "/events"): self = .events
        case (.head, "/health"): self = .health
        default: return nil
        }
    }
}
