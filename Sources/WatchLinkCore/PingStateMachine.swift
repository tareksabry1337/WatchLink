package struct PingStateMachine: Sendable {
    let maxPingFailures: Int
    private(set) var consecutiveFailures = 0
    private(set) var reconnectAttempt = 0
    private(set) var isReconnecting = false

    package init(maxPingFailures: Int) {
        self.maxPingFailures = maxPingFailures
    }

    package mutating func nextAction(after result: PingResult) -> PingAction {
        switch result {
        case .success:
            consecutiveFailures = 0
            if isReconnecting {
                isReconnecting = false
                reconnectAttempt = 0
            }
            return .sendPing

        case .failure:
            if isReconnecting {
                reconnectAttempt += 1
                return .reconnect(attempt: reconnectAttempt)
            }

            consecutiveFailures += 1
            if consecutiveFailures >= maxPingFailures {
                isReconnecting = true
                reconnectAttempt = 1
                return .reconnect(attempt: 1)
            }
            return .sendPing
        }
    }

    package mutating func reset() {
        consecutiveFailures = 0
        reconnectAttempt = 0
        isReconnecting = false
    }
}
