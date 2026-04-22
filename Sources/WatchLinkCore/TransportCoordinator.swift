import Foundation

@WatchLinkActor
package final class TransportCoordinator {
    package private(set) var transports: [any Transport]
    private let clock: AnyClock
    private let retryInterval: Duration
    private let logger: WatchLinkLogger
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var seenIDs: Set<String> = []
    private var reachabilityTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var subscriptions: [Channel: [UUID: @Sendable (Data, String) -> Void]] = [:]
    private var controlHandler: (@WatchLinkActor (ControlFrame) -> Void)?
    private var heartbeatHandler: (@WatchLinkActor () -> Void)?
    private var ingestionTask: Task<Void, Never>?
    private var unackedMessages: [String: UnackedEntry] = [:]
    private var pendingConfirmations: Set<String> = []
    private var sendTasks: [Task<Void, Never>] = []

    private struct UnackedEntry {
        let data: Data
    }

    package nonisolated init(
        transports: [any Transport],
        clock: AnyClock = AnyClock(),
        retryInterval: Duration = .seconds(5),
        logger: WatchLinkLogger = .osLog
    ) {
        self.transports = transports
        self.clock = clock
        self.retryInterval = retryInterval
        self.logger = logger
    }

    package func startAll() {
        for transport in transports {
            transport.start()
        }

        ingestionTask = Task { [weak self] in
            await self?.ingest()
        }

        reachabilityTask = Task { [weak self] in
            await self?.observeReachability()
        }

        retryTask = Task { [weak self] in
            await self?.retryLoop()
        }
    }

    package func stopAll() async {
        for transport in transports {
            transport.stop()
        }

        ingestionTask?.cancel()
        reachabilityTask?.cancel()
        retryTask?.cancel()

        await ingestionTask?.value
        await reachabilityTask?.value
        await retryTask?.value

        reachabilityTask = nil
        ingestionTask = nil
        retryTask = nil
        controlHandler = nil
        heartbeatHandler = nil

        for task in sendTasks { task.cancel() }
        sendTasks.removeAll()

        subscriptions.removeAll()
        seenIDs.removeAll()
        unackedMessages.removeAll()
        pendingConfirmations.removeAll()
    }

    package func onControl(_ handler: @escaping @WatchLinkActor (ControlFrame) -> Void) {
        controlHandler = handler
    }

    package func onHeartbeat(_ handler: @escaping @WatchLinkActor () -> Void) {
        heartbeatHandler = handler
    }

    package func send<M: WatchLinkMessage>(_ message: M) throws where M.Response == NoResponse {
        let confirmations = flushConfirmations()
        let frame = try Frame(wrapping: message, encoder: encoder, confirmedAcks: confirmations)
        let data = try encoder.encode(frame)
        unackedMessages[frame.id] = UnackedEntry(data: data)
        logger.debug("Send \(frame.id) on \(M.channel)")
        sendOrWait(data)
    }

    package func send<M: WatchLinkMessage>(
        _ message: M,
        timeout: Duration = .seconds(30)
    ) async throws -> M.Response {
        let confirmations = flushConfirmations()
        let frame = try Frame(wrapping: message, encoder: encoder, confirmedAcks: confirmations)
        let data = try encoder.encode(frame)
        unackedMessages[frame.id] = UnackedEntry(data: data)
        logger.debug("Query \(frame.id) on \(M.channel)")

        let responseData = try await withThrowingTaskGroup(of: Data?.self) { group in
            for transport in transports {
                group.addTask {
                    try? await transport.request(data)
                }
            }

            group.addTask { [clock] in
                try await clock.sleep(for: timeout)
                throw WatchLinkError.requestTimedOut
            }

            for try await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }

            throw WatchLinkError.requestTimedOut
        }

        return try decoder.decode(M.Response.self, from: responseData)
    }

    package func reply<M: WatchLinkMessage>(with message: M, to frameID: String) async throws {
        let data = try encoder.encode(message)
        await withTaskGroup(of: Void.self) { group in
            for transport in transports {
                group.addTask {
                    await transport.reply(to: frameID, with: data)
                }
            }
        }
    }

    package func sendControl(_ controlFrame: ControlFrame) throws {
        let confirmations = flushConfirmations()
        let frame = try Frame(control: controlFrame, encoder: encoder, confirmedAcks: confirmations)
        let data = try encoder.encode(frame)

        var reachable: [any Transport] = []
        for transport in transports {
            if transport.isReachable {
                reachable.append(transport)
            }
        }

        guard !reachable.isEmpty else { return }
        sendToReachable(data, reachable: reachable)
    }

    package var diagnosticsPendingCount: Int {
        unackedMessages.count
    }

    package var diagnosticsSeenIDsCount: Int { seenIDs.count }
    package var diagnosticsUnackedCount: Int { unackedMessages.count }
    package var diagnosticsPendingConfirmationsCount: Int { pendingConfirmations.count }

    package func hasReachableTransport() -> Bool {
        for transport in transports {
            if transport.isReachable { return true }
        }
        return false
    }

    private func flushConfirmations() -> [String] {
        let confirmations = Array(pendingConfirmations)
        pendingConfirmations.removeAll()
        return confirmations
    }

    private func sendOrWait(_ data: Data) {
        var reachable: [any Transport] = []
        for transport in transports {
            if transport.isReachable {
                reachable.append(transport)
            }
        }

        guard !reachable.isEmpty else {
            logger.debug("No reachable transports, waiting for retry (unacked: \(self.unackedMessages.count))")
            return
        }

        sendToReachable(data, reachable: reachable)
    }

    private func sendToReachable(_ data: Data, reachable: [any Transport]) {
        let task = Task { [logger] in
            var anySucceeded = false

            await withTaskGroup(of: Bool.self) { group in
                for transport in reachable {
                    group.addTask {
                        do {
                            try await transport.send(data)
                            return true
                        } catch {
                            return false
                        }
                    }
                }

                for await succeeded in group {
                    if succeeded { anySucceeded = true }
                }
            }

            if !anySucceeded {
                logger.warning("All \(reachable.count) transports failed to send")
            }
        }
        sendTasks.removeAll { $0.isCancelled }
        sendTasks.append(task)
    }

    private func observeReachability() async {
        let streams = transports.map(\.reachabilityChanges)

        await withTaskGroup(of: Void.self) { group in
            for stream in streams {
                group.addTask { [weak self] in
                    for await reachable in stream {
                        if reachable {
                            await self?.retryUnacked()
                        }
                    }
                }
            }

            await group.waitForAll()
        }
    }

    package func messages<M: WatchLinkMessage>(_ type: M.Type) -> AsyncStream<ReceivedMessage<M>> {
        let subID = UUID()
        let decoder = self.decoder

        return AsyncStream { continuation in
            subscribe(id: subID, channel: M.channel) { data, frameID in
                if let message = try? decoder.decode(M.self, from: data) {
                    continuation.yield(ReceivedMessage(value: message, frameID: frameID))
                }
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.unsubscribe(id: subID, channel: M.channel)
                }
            }
        }
    }

    private func ingest() async {
        let streams = transports.map { $0.incoming() }

        await withTaskGroup(of: Void.self) { group in
            for stream in streams {
                group.addTask { [weak self] in
                    for await incoming in stream {
                        await self?.route(incoming)
                    }
                }
            }

            await group.waitForAll()
        }
    }

    private func route(_ incoming: IncomingMessage) {
        let frame: Frame
        do {
            frame = try decoder.decode(Frame.self, from: incoming.data)
        } catch {
            logger.warning("Failed to decode frame: \(error)")
            return
        }

        heartbeatHandler?()

        // Process piggybacked ack confirmations
        for id in frame.confirmedAcks {
            seenIDs.remove(id)
        }

        switch frame.kind {
        case .control:
            // Control frames are idempotent — no dedup needed
            do {
                let control = try decoder.decode(ControlFrame.self, from: frame.payload)
                switch control {
                case .ack(let ackedID):
                    if unackedMessages.removeValue(forKey: ackedID) != nil {
                        logger.debug("Acked \(ackedID) (unacked: \(self.unackedMessages.count))")
                    }
                    pendingConfirmations.insert(ackedID)
                default:
                    controlHandler?(control)
                }
            } catch {
                logger.warning("Failed to decode control frame: \(error)")
            }

        case .message:
            guard let channel = frame.channel else {
                logger.warning("Message frame missing channel: \(frame.id)")
                return
            }

            // Always send ack — the sender needs it to stop retrying
            try? sendControl(.ack(frame.id))

            // Dedup: only deliver to subscribers once
            guard dedup(frame.id) else {
                logger.debug("Dedup dropped \(frame.id)")
                return
            }

            guard let channelSubs = subscriptions[channel] else { return }
            for (_, callback) in channelSubs {
                callback(frame.payload, frame.id)
            }
        }
    }

    private func subscribe(
        id: UUID,
        channel: Channel,
        handler: @escaping @Sendable (Data, String) -> Void
    ) {
        subscriptions[channel, default: [:]][id] = handler
    }

    private func unsubscribe(id: UUID, channel: Channel) {
        subscriptions[channel]?[id] = nil
        if subscriptions[channel]?.isEmpty == true {
            subscriptions[channel] = nil
        }
    }

    private func dedup(_ id: String) -> Bool {
        guard !seenIDs.contains(id) else { return false }
        seenIDs.insert(id)
        return true
    }

    private func retryLoop() async {
        while !Task.isCancelled {
            try? await clock.sleep(for: retryInterval)
            guard !Task.isCancelled else { return }
            retryUnacked()
        }
    }

    private func retryUnacked() {
        guard !unackedMessages.isEmpty else { return }

        var reachable: [any Transport] = []
        for transport in transports {
            if transport.isReachable {
                reachable.append(transport)
            }
        }
        guard !reachable.isEmpty else { return }

        logger.debug("Retrying \(self.unackedMessages.count) unacked messages")
        for (_, entry) in unackedMessages {
            sendToReachable(entry.data, reachable: reachable)
        }
    }
}
