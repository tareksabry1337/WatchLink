import Foundation

package struct IncomingMessage: Sendable {
    package let data: Data
    package let replyHandler: (@Sendable (Data) -> Void)?

    package init(data: Data, replyHandler: (@Sendable (Data) -> Void)? = nil) {
        self.data = data
        self.replyHandler = replyHandler
    }
}
