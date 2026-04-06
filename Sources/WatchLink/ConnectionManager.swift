import Foundation
import WatchLinkCore

actor ConnectionManager {
    private let coordinator: TransportCoordinator
    private let config: WatchLinkConfiguration
    private var stateMachine: PingStateMachine
    private var state: ConnectionState = .disconnected
    private var stateSubscribers: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]
    private var loopTask: Task<Void, Never>?
    private var lastReceivedAt: ContinuousClock.Instant?

    init(coordinator: TransportCoordinator, config: WatchLinkConfiguration) {
        self.coordinator = coordinator
        self.config = config
        self.stateMachine = PingStateMachine(
            maxPingFailures: config.maxPingFailures,
            maxRetries: config.maxRetries
        )
    }

    var connectionState: AsyncStream<ConnectionState> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.yield(state)
            stateSubscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.removeStateSubscriber(id) }
            }
        }
    }

    private func removeStateSubscriber(_ id: UUID) {
        stateSubscribers[id] = nil
    }

    func connect() async {
        updateState(.connecting)
        stateMachine.reset()
        startLoop()
    }

    func disconnect() {
        loopTask?.cancel()
        loopTask = nil
        stateMachine.reset()
        lastReceivedAt = nil
        updateState(.disconnected)
    }

    func heartbeatReceived() {
        lastReceivedAt = .now
        updateState(.connected)
    }

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    private func runLoop() async {
        let timeout = config.pingInterval * 3

        while !Task.isCancelled {
            try? await coordinator.sendControl(.ping)
            try? await config.clock.sleep(for: config.pingInterval)
            guard !Task.isCancelled else { return }

            if state == .connecting { continue }

            guard let lastReceived = lastReceivedAt else { continue }
            let elapsed = ContinuousClock.now - lastReceived

            if elapsed > timeout {
                switch stateMachine.nextAction(after: .failure) {
                case .sendPing:
                    break
                case .reconnect(let attempt):
                    updateState(.reconnecting(attempt: attempt))
                case .giveUp:
                    updateState(.disconnected)
                    return
                }
            }
        }
    }

    private func updateState(_ newState: ConnectionState) {
        guard newState != state else { return }
        state = newState
        for (_, continuation) in stateSubscribers {
            continuation.yield(newState)
        }
    }
}
