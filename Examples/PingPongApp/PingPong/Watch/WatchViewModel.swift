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
    private(set) var entries: [String] = []

    @ObservationIgnored
    private lazy var link: WatchLink = WatchLink { [weak self] config in
        config.transports = [.watchConnectivity, .http]
        config.bleServiceUUID = BLEConstants.serviceUUID
        config.bleIPCharacteristicUUID = BLEConstants.ipCharacteristicUUID
        config.httpPort = 8188
        config.pingInterval = .seconds(10)
        config.logger = WatchLinkLogger { level, message in
            Task { @MainActor in
                self?.addEntry("[\(level)] \(message)")
            }
        }
    }

    func start() async {
        addEntry("Starting WatchLink...")

        async let state: Void = observeState()
        async let pongs: Void = listenForPongs()

        await link.connect()

        _ = await (state, pongs)
    }

    func sendPing() async {
        pingCount += 1
        let ping = Ping(count: pingCount, sentAt: Date())
        do {
            try await link.send(ping)
            addEntry("Sent ping #\(pingCount)")
        } catch {
            addEntry("Ping failed: \(error)")
        }
    }

    func sendHeartRate() async {
        let bpm = Int.random(in: 60...180)
        do {
            try await link.send(HeartRate(bpm: bpm))
            addEntry("Sent HR: \(bpm)")
        } catch {
            addEntry("HR failed: \(error)")
        }
    }

    private func observeState() async {
        for await state in await link.connectionState {
            connectionState = state.description
            addEntry("State: \(state.description)")
        }
    }

    private func listenForPongs() async {
        for await pong in await link.messages(Pong.self) {
            pongCount += 1
            lastRoundTripMs = pong.value.roundTripMs
            addEntry("Pong #\(pong.value.count) (\(pong.value.roundTripMs)ms)")
        }
    }

    func addEntry(_ message: String) {
        entries.insert(message, at: 0)
        if entries.count > 50 { entries.removeLast() }
    }
}
