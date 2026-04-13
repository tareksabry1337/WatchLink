import Foundation

package protocol WCSessionProtocol: Sendable {
    var isActivatedAndReachable: Bool { get }
    func activate()
    func sendMessageData(
        _ data: Data,
        replyHandler: (@Sendable (Data) -> Void)?,
        errorHandler: (@Sendable (any Error) -> Void)?
    )
}
