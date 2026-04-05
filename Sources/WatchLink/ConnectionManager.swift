import Foundation
import WatchLinkCore

actor ConnectionManager {
    private let coordinator: TransportCoordinator
    private let config: WatchLinkConfiguration
    private var stateMachine: PingStateMachine
    private var state: ConnectionState = .disconnected
    private var stateSubscribers: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]
    private var pingTask: Task<Void, Never>?

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
        try? await coordinator.sendControl(.ping)
        stateMachine.reset()
        updateState(.connected)
        startPingLoop()
    }

    func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        stateMachine.reset()
        updateState(.disconnected)
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            try? await config.clock.sleep(for: config.pingInterval)
            guard !Task.isCancelled else { return }

            let result: PingResult
            do {
                try await coordinator.sendControl(.ping)
                result = .success
            } catch {
                result = .failure
            }

            switch stateMachine.nextAction(after: result) {
            case .sendPing:
                updateState(.connected)
            case .reconnect(let attempt):
                updateState(.reconnecting(attempt: attempt))
            case .giveUp:
                updateState(.disconnected)
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
