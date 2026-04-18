import Foundation
@testable import WatchLinkCore

public func encodeFrame<M: WatchLinkMessage>(_ message: M, confirmedAcks: [String] = []) throws -> Data {
    let encoder = JSONEncoder()
    let frame = try Frame(wrapping: message, encoder: encoder, confirmedAcks: confirmedAcks)
    return try encoder.encode(frame)
}

public func encodeControlFrame(_ control: ControlFrame, confirmedAcks: [String] = []) throws -> Data {
    let encoder = JSONEncoder()
    let frame = try Frame(control: control, encoder: encoder, confirmedAcks: confirmedAcks)
    return try encoder.encode(frame)
}
