import Foundation

package actor TransportCoordinator {
    private(set) var transports: [any Transport]
    private let clock: AnyClock
    private let sweepInterval: Duration
    private let logger: WatchLinkLogger
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var seenIDs: Set<String> = []
    private var sweepTask: Task<Void, Never>?
    private var reachabilityTask: Task<Void, Never>?
    private var subscriptions: [Channel: [UUID: @Sendable (Data, String) -> Void]] = [:]
    private var controlHandler: (@Sendable (ControlFrame) -> Void)?
    private var heartbeatHandler: (@Sendable () -> Void)?
    private var ingestionTask: Task<Void, Never>?
    private var pendingQueue: [Data] = []
    private var replyHandlers: [String: @Sendable (Data) -> Void] = [:]

    package init(
        transports: [any Transport],
        clock: AnyClock = AnyClock(ContinuousClock()),
        sweepInterval: Duration = .seconds(30),
        logger: WatchLinkLogger = .osLog
    ) {
        self.transports = transports
        self.clock = clock
        self.sweepInterval = sweepInterval
        self.logger = logger
    }

    package func startAll() async {
        for transport in transports {
            await transport.start()
        }

        ingestionTask = Task { [weak self] in
            await self?.ingest()
        }

        sweepTask = Task { [weak self] in
            await self?.sweepLoop()
        }

        reachabilityTask = Task { [weak self] in
            await self?.watchReachability()
        }
    }

    package func stopAll() async {
        for transport in transports {
            await transport.stop()
        }

        ingestionTask?.cancel()
        sweepTask?.cancel()
        reachabilityTask?.cancel()

        await ingestionTask?.value
        await sweepTask?.value
        await reachabilityTask?.value

        reachabilityTask = nil
        ingestionTask = nil
        sweepTask = nil
        controlHandler = nil
        heartbeatHandler = nil

        subscriptions.removeAll()
        seenIDs.removeAll()
        pendingQueue.removeAll()
        replyHandlers.removeAll()
    }

    package func onControl(_ handler: @escaping @Sendable (ControlFrame) -> Void) {
        controlHandler = handler
    }

    package func onHeartbeat(_ handler: @escaping @Sendable () -> Void) {
        heartbeatHandler = handler
    }

    package func send<M: WatchLinkMessage>(_ message: M) async throws {
        let frame = try Frame(wrapping: message, encoder: encoder)
        let data = try encoder.encode(frame)
        await fanOut(data)
    }

    package func reply<M: WatchLinkMessage>(toFrameID frameID: String, with message: M) async throws {
        let frame = try Frame(wrapping: message, encoder: encoder)
        let data = try encoder.encode(frame)

        if let handler = replyHandlers.removeValue(forKey: frameID) {
            handler(data)
        }

        await fanOut(data)
    }

    package func sendControl(_ frame: ControlFrame) async throws {
        let f = try Frame(control: frame, encoder: encoder)
        let data = try encoder.encode(f)
        await fanOut(data)
    }

    package func hasReachableTransport() async -> Bool {
        for transport in transports {
            if await transport.isReachable { return true }
        }
        return false
    }

    private func fanOut(_ data: Data) async {
        var reachable: [any Transport] = []
        for transport in transports {
            if await transport.isReachable {
                reachable.append(transport)
            }
        }

        guard !reachable.isEmpty else {
            pendingQueue.append(data)
            return
        }

        sendToReachable(data, reachable: reachable)
    }

    private func sendToReachable(_ data: Data, reachable: [any Transport]) {
        Task { [weak self] in
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
                await self?.enqueue(data)
            }
        }
    }

    private func enqueue(_ data: Data) {
        pendingQueue.append(data)
    }

    private func watchReachability() async {
        await withTaskGroup(of: Void.self) { group in
            for transport in transports {
                group.addTask { [weak self] in
                    guard let self else { return }
                    for await reachable in await transport.reachabilityChanges {
                        if reachable {
                            await self.flushPending()
                        }
                    }
                }
            }

            await group.waitForAll()
        }
    }

    private func flushPending() async {
        guard !pendingQueue.isEmpty else { return }

        var reachable: [any Transport] = []
        for transport in transports {
            if await transport.isReachable {
                reachable.append(transport)
            }
        }
        guard !reachable.isEmpty else { return }

        let pending = pendingQueue
        pendingQueue = []

        for data in pending {
            sendToReachable(data, reachable: reachable)
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
        await withTaskGroup(of: Void.self) { group in
            for transport in transports {
                group.addTask { [weak self] in
                    guard let self else { return }
                    for await incoming in await transport.incoming() {
                        await self.route(incoming)
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

        if let handler = incoming.replyHandler {
            replyHandlers[frame.id] = handler
        }

        heartbeatHandler?()

        switch frame.kind {
        case .control:
            do {
                let control = try decoder.decode(ControlFrame.self, from: frame.payload)
                controlHandler?(control)
            } catch {
                logger.warning("Failed to decode control frame: \(error)")
            }

        case .message:
            guard let channel = frame.channel else {
                logger.warning("Message frame missing channel: \(frame.id)")
                return
            }
            
            guard dedup(frame.id) else { return }
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

    private func sweepLoop() async {
        while !Task.isCancelled {
            try? await clock.sleep(for: sweepInterval)
            guard !Task.isCancelled else { return }
            seenIDs.removeAll()
            replyHandlers.removeAll()
        }
    }
}
