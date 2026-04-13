import Foundation

package struct Frame: Codable, Sendable {
    package enum Kind: String, Codable, Sendable {
        case message
        case control
    }

    package let kind: Kind
    package let id: String
    package let channel: Channel?
    package let payload: Data
    package let confirmedAcks: [String]

    package init<M: WatchLinkMessage>(
        wrapping message: M,
        encoder: JSONEncoder,
        confirmedAcks: [String]
    ) throws {
        self.kind = .message
        self.id = UUID().uuidString
        self.channel = M.channel
        self.payload = try encoder.encode(message)
        self.confirmedAcks = confirmedAcks
    }

    package init(
        control frame: ControlFrame,
        encoder: JSONEncoder,
        confirmedAcks: [String]
    ) throws {
        self.kind = .control
        self.id = UUID().uuidString
        self.channel = nil
        self.payload = try encoder.encode(frame)
        self.confirmedAcks = confirmedAcks
    }
}
