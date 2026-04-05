import Foundation

struct Frame: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case message
        case control
    }

    let kind: Kind
    let id: String
    let channel: Channel?
    let payload: Data

    init<M: WatchLinkMessage>(wrapping message: M, encoder: JSONEncoder) throws {
        self.kind = .message
        self.id = UUID().uuidString
        self.channel = M.channel
        self.payload = try encoder.encode(message)
    }

    init(control frame: ControlFrame, encoder: JSONEncoder) throws {
        self.kind = .control
        self.id = UUID().uuidString
        self.channel = nil
        self.payload = try encoder.encode(frame)
    }
}
