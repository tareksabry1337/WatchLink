import Testing
@testable import WatchLinkCore

@Suite("PingStateMachine")
struct PingStateMachineTests {

    // MARK: - Normal Pinging

    @Test("success keeps sending pings")
    func successContinues() {
        var machine = PingStateMachine(maxPingFailures: 3, maxRetries: 2)
        #expect(machine.nextAction(after: .success) == .sendPing)
        #expect(machine.nextAction(after: .success) == .sendPing)
        #expect(machine.consecutiveFailures == 0)
    }

    @Test("failures below threshold keep sending pings")
    func failuresBelowThreshold() {
        var machine = PingStateMachine(maxPingFailures: 3, maxRetries: 2)
        #expect(machine.nextAction(after: .failure) == .sendPing)
        #expect(machine.nextAction(after: .failure) == .sendPing)
        #expect(machine.consecutiveFailures == 2)
    }

    @Test("success resets consecutive failures")
    func successResetsFailures() {
        var machine = PingStateMachine(maxPingFailures: 3, maxRetries: 2)
        _ = machine.nextAction(after: .failure)
        _ = machine.nextAction(after: .failure)
        _ = machine.nextAction(after: .success)
        #expect(machine.consecutiveFailures == 0)
    }

    // MARK: - Transition to Reconnecting

    @Test("enters reconnect after max ping failures")
    func reconnectAfterMaxFailures() {
        var machine = PingStateMachine(maxPingFailures: 3, maxRetries: 2)
        #expect(machine.nextAction(after: .failure) == .sendPing)
        #expect(machine.nextAction(after: .failure) == .sendPing)
        #expect(machine.nextAction(after: .failure) == .reconnect(attempt: 1))
        #expect(machine.isReconnecting)
    }

    @Test("enters reconnect after single failure when maxPingFailures is 1")
    func singleFailureThreshold() {
        var machine = PingStateMachine(maxPingFailures: 1, maxRetries: 3)
        #expect(machine.nextAction(after: .failure) == .reconnect(attempt: 1))
    }

    // MARK: - Reconnection Attempts

    @Test("continued failures increment reconnect attempts")
    func reconnectAttempts() {
        var machine = PingStateMachine(maxPingFailures: 1, maxRetries: 3)
        #expect(machine.nextAction(after: .failure) == .reconnect(attempt: 1))
        #expect(machine.nextAction(after: .failure) == .reconnect(attempt: 2))
        #expect(machine.nextAction(after: .failure) == .reconnect(attempt: 3))
    }

    @Test("gives up after max retries exhausted")
    func givesUpAfterMaxRetries() {
        var machine = PingStateMachine(maxPingFailures: 1, maxRetries: 2)
        #expect(machine.nextAction(after: .failure) == .reconnect(attempt: 1))
        #expect(machine.nextAction(after: .failure) == .reconnect(attempt: 2))
        #expect(machine.nextAction(after: .failure) == .giveUp)
    }

    // MARK: - Recovery

    @Test("successful reconnect resets everything")
    func reconnectSuccess() {
        var machine = PingStateMachine(maxPingFailures: 1, maxRetries: 3)
        #expect(machine.nextAction(after: .failure) == .reconnect(attempt: 1))
        #expect(machine.nextAction(after: .success) == .sendPing)
        #expect(machine.isReconnecting == false)
        #expect(machine.reconnectAttempt == 0)
        #expect(machine.consecutiveFailures == 0)
    }

    @Test("after recovery, failures start fresh")
    func failuresAfterRecovery() {
        var machine = PingStateMachine(maxPingFailures: 2, maxRetries: 3)

        _ = machine.nextAction(after: .failure)
        _ = machine.nextAction(after: .failure)
        #expect(machine.isReconnecting)

        _ = machine.nextAction(after: .success)

        #expect(machine.nextAction(after: .failure) == .sendPing)
        #expect(machine.consecutiveFailures == 1)
    }

    // MARK: - Reset

    @Test("reset clears all state")
    func reset() {
        var machine = PingStateMachine(maxPingFailures: 1, maxRetries: 2)
        _ = machine.nextAction(after: .failure)
        _ = machine.nextAction(after: .failure)

        machine.reset()

        #expect(machine.consecutiveFailures == 0)
        #expect(machine.reconnectAttempt == 0)
        #expect(machine.isReconnecting == false)
    }

    // MARK: - Edge Cases

    @Test("maxPingFailures of 0 immediately reconnects on first failure")
    func zeroPingFailures() {
        var machine = PingStateMachine(maxPingFailures: 0, maxRetries: 1)
        #expect(machine.nextAction(after: .failure) == .reconnect(attempt: 1))
    }

    @Test("maxRetries of 0 gives up on first reconnect failure")
    func zeroRetries() {
        var machine = PingStateMachine(maxPingFailures: 1, maxRetries: 0)
        #expect(machine.nextAction(after: .failure) == .reconnect(attempt: 1))
        #expect(machine.nextAction(after: .failure) == .giveUp)
    }

    @Test("full lifecycle: ping → fail → reconnect → recover → fail → give up")
    func fullLifecycle() {
        var machine = PingStateMachine(maxPingFailures: 2, maxRetries: 1)

        // Normal pinging
        #expect(machine.nextAction(after: .success) == .sendPing)

        // Failures accumulate
        #expect(machine.nextAction(after: .failure) == .sendPing)
        #expect(machine.nextAction(after: .failure) == .reconnect(attempt: 1))

        // Reconnect succeeds
        #expect(machine.nextAction(after: .success) == .sendPing)

        // Fails again
        #expect(machine.nextAction(after: .failure) == .sendPing)
        #expect(machine.nextAction(after: .failure) == .reconnect(attempt: 1))

        // This time reconnect fails too
        #expect(machine.nextAction(after: .failure) == .giveUp)
    }
}
