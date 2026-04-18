import Foundation
@testable import WatchLinkCore

public final class MockWCSession: WCSessionProtocol, @unchecked Sendable {
    public var isActivatedAndReachable: Bool = true
    public var activateCalled = false
    public var sentData: [Data] = []
    public var shouldFail = false
    public var replyData: Data?
    public var replyError: Error?

    public init() {}

    public func activate() {
        activateCalled = true
    }

    public func sendMessageData(
        _ data: Data,
        replyHandler: (@Sendable (Data) -> Void)?,
        errorHandler: (@Sendable (any Error) -> Void)?
    ) {
        if shouldFail {
            errorHandler?(WatchLinkError.sendFailed("Mock WC failure"))
            return
        }
        sentData.append(data)
        if let replyError {
            errorHandler?(replyError)
        } else if let replyData {
            replyHandler?(replyData)
        }
    }
}
