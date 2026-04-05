import Testing
import Foundation
@testable import WatchLinkCore

@Suite("Channel")
struct ChannelTests {
    @Test("string literal initialization")
    func stringLiteral() {
        let channel: Channel = "workout.heartRate"
        #expect(channel.value == "workout.heartRate")
    }

    @Test("explicit string initialization")
    func explicitInit() {
        let name = "settings.sync"
        let channel = Channel(name)
        #expect(channel.value == "settings.sync")
    }

    @Test("description matches value")
    func description() {
        let channel: Channel = "test.channel"
        #expect(channel.description == "test.channel")
    }

    @Test("hashable — equal channels hash the same")
    func hashable() {
        let a: Channel = "same"
        let b: Channel = "same"
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("hashable — different channels differ")
    func hashableDifferent() {
        let a: Channel = "one"
        let b: Channel = "two"
        #expect(a != b)
    }

    @Test("usable as dictionary key")
    func dictionaryKey() {
        var dict: [Channel: Int] = [:]
        dict["alpha"] = 1
        dict["beta"] = 2
        #expect(dict["alpha"] == 1)
        #expect(dict["beta"] == 2)
    }

    @Test("codable round-trip")
    func codable() throws {
        let original: Channel = "workout.heartRate"
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Channel.self, from: data)
        #expect(original == decoded)
    }

    @Test("encodes as plain string in JSON")
    func encodesAsString() throws {
        let channel: Channel = "test"
        let data = try JSONEncoder().encode(channel)
        let json = String(data: data, encoding: .utf8)
        #expect(json == "\"test\"")
    }
}
