import Foundation
import WatchLink
import WatchLinkCore

@MainActor
final class WatchViewModel: ObservableObject {
    @Published private(set) var connectionState = "Disconnected"
    @Published private(set) var pingCount = 0
    @Published private(set) var lastRoundTripMs = 0
    @Published private(set) var pongCount = 0
    @Published private(set) var phoneTime = "—"
    @Published private(set) var entries: [String] = []
    @Published private(set) var diag = WatchLinkDiagnostics()

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
        async let diagLoop: Void = refreshDiagnostics()

        await link.connect()

        _ = await (state, pongs, diagLoop)
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

    func queryTime() async {
        do {
            let response = try await link.send(TimeRequest())
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            phoneTime = formatter.string(from: response.timestamp)
            addEntry("Phone time: \(phoneTime) (\(response.label))")
        } catch {
            addEntry("Time query failed: \(error)")
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

    private func refreshDiagnostics() async {
        while true {
            diag = await link.diagnostics()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    func addEntry(_ message: String) {
        entries.insert(message, at: 0)
        if entries.count > 50 { entries.removeLast() }
    }
}
