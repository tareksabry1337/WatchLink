import Foundation
@testable import WatchLinkCore

public final class MockReplyHandler: @unchecked Sendable {
    public private(set) var replies: [Data] = []
    public var callCount: Int { replies.count }

    public init() {}

    public var handler: @Sendable (Data) -> Void {
        { [self] data in self.replies.append(data) }
    }

    public func decodeFirstReply<M: WatchLinkMessage>(_ type: M.Type = M.self) throws -> M {
        let frame = try JSONDecoder().decode(Frame.self, from: replies[0])
        return try JSONDecoder().decode(M.self, from: frame.payload)
    }
}
