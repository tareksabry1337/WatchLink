import Foundation
@testable import WatchLinkCore

public struct PingMessage: WatchLinkMessage {
    public let count: Int
    public init(count: Int) { self.count = count }
}

public struct PongMessage: WatchLinkMessage {
    public let count: Int
    public init(count: Int) { self.count = count }
}

public struct AskMessage: WatchLinkMessage {
    public typealias Response = AnswerMessage
    public let question: String
    public init(question: String) { self.question = question }
}

public struct AnswerMessage: WatchLinkMessage {
    public let answer: String
    public init(answer: String) { self.answer = answer }
}
