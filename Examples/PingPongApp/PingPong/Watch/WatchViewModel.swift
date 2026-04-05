import Foundation
import WatchLink
import WatchLinkCore

@Observable
@MainActor
final class WatchViewModel {
    private(set) var connectionState = "Disconnected"
    private(set) var pingCount = 0
    private(set) var lastRoundTripMs = 0
    private(set) var pongCount = 0
    private(set) var log: [String] = []

    private let link = WatchLink { config in
        config.transports = [.http]
        config.bleServiceUUID = BLEConstants.serviceUUID
        config.bleIPCharacteristicUUID = BLEConstants.ipCharacteristicUUID
        config.httpPort = 8188
        config.pingInterval = .seconds(10)
    }

    func start() async {
        addLog("Connecting...")
        await link.connect()
        addLog("Connected")

        async let state: Void = observeState()
        async let pongs: Void = listenForPongs()
        _ = await (state, pongs)
    }

    func sendPing() async {
        pingCount += 1
        let ping = Ping(count: pingCount, sentAt: Date())
        do {
            try await link.send(ping)
            addLog("Sent ping #\(pingCount)")
        } catch {
            addLog("Ping failed: \(error)")
        }
    }

    func sendHeartRate() async {
        let bpm = Int.random(in: 60...180)
        do {
            try await link.send(HeartRate(bpm: bpm))
            addLog("Sent HR: \(bpm)")
        } catch {
            addLog("HR failed: \(error)")
        }
    }

    private func observeState() async {
        for await state in await link.connectionState {
            connectionState = state.description
        }
    }

    private func listenForPongs() async {
        for await pong in await link.messages(Pong.self) {
            pongCount += 1
            lastRoundTripMs = pong.roundTripMs
            addLog("Pong #\(pong.count) (\(pong.roundTripMs)ms)")
        }
    }

    private func addLog(_ message: String) {
        log.insert(message, at: 0)
        if log.count > 30 { log.removeLast() }
    }
}
