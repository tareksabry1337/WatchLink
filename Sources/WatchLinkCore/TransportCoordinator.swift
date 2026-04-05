import Foundation

public actor TransportCoordinator {
    private(set) var transports: [any Transport]
    private let clock: AnyClock
    private let sweepInterval: Duration
    private let logger: WatchLinkLogger
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var seenIDs: Set<String> = []
    private var sweepTask: Task<Void, Never>?
    private var reachabilityTask: Task<Void, Never>?
    private var subscriptions: [Channel: [UUID: @Sendable (Data) -> Void]] = [:]
    private var controlHandler: (@Sendable (ControlFrame) -> Void)?
    private var ingestionTask: Task<Void, Never>?
    private var pendingQueue: [Data] = []

    public init(
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

    public func startAll() async {
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

    public func stopAll() async {
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
        
        subscriptions.removeAll()
        seenIDs.removeAll()
        pendingQueue.removeAll()
    }

    public func onControl(_ handler: @escaping @Sendable (ControlFrame) -> Void) {
        controlHandler = handler
    }

    public func send<M: WatchLinkMessage>(_ message: M) async throws {
        let frame = try Frame(wrapping: message, encoder: encoder)
        let data = try encoder.encode(frame)
        await sendRaw(data)
    }

    public func sendControl(_ frame: ControlFrame) async throws {
        let f = try Frame(control: frame, encoder: encoder)
        let data = try encoder.encode(f)
        await sendRaw(data)
    }

    public func hasReachableTransport() async -> Bool {
        for transport in transports {
            if await transport.isReachable { return true }
        }
        return false
    }

    private func sendRaw(_ data: Data) async {
        var reachable: [any Transport] = []
        for transport in transports {
            if await transport.isReachable {
                reachable.append(transport)
            }
        }

        guard !reachable.isEmpty else {
            pendingQueue.append(data)
            logger.debug("No reachable transport, queued message (\(pendingQueue.count) pending)")
            return
        }

        do {
            try await sendToReachable(data, reachable: reachable)
        } catch {
            pendingQueue.append(data)
            logger.warning("Send failed, queued message: \(error)")
        }
    }

    private func sendToReachable(_ data: Data, reachable: [any Transport]) async throws {
        if reachable.count == 1 {
            try await reachable[0].send(data)
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for transport in reachable {
                group.addTask {
                    try await transport.send(data)
                }
            }

            var lastError: Error?
            while let result = await group.nextResult() {
                switch result {
                case .success:
                    group.cancelAll()
                    return
                    
                case .failure(let error):
                    lastError = error
                }
            }

            if let error = lastError {
                throw error
            }
        }
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
        logger.debug("Flushing \(pending.count) pending messages")

        for data in pending {
            do {
                try await sendToReachable(data, reachable: reachable)
            } catch {
                pendingQueue.append(data)
            }
        }
    }

    public func messages<M: WatchLinkMessage>(_ type: M.Type) -> AsyncStream<M> {
        let subID = UUID()
        let decoder = self.decoder

        return AsyncStream { continuation in
            subscribe(id: subID, channel: M.channel) { data in
                if let message = try? decoder.decode(M.self, from: data) {
                    continuation.yield(message)
                }
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.unsubscribe(id: subID, channel: M.channel) }
            }
        }
    }

    private func ingest() async {
        await withTaskGroup(of: Void.self) { group in
            for transport in transports {
                group.addTask { [weak self] in
                    guard let self else { return }
                    for await data in await transport.incoming() {
                        await self.route(data)
                    }
                }
            }
            
            await group.waitForAll()
        }
    }

    private func route(_ data: Data) {
        let frame: Frame
        do {
            frame = try decoder.decode(Frame.self, from: data)
        } catch {
            logger.warning("Failed to decode frame: \(error)")
            return
        }

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
                callback(frame.payload)
            }
        }
    }

    private func subscribe(
        id: UUID,
        channel: Channel,
        handler: @escaping @Sendable (Data) -> Void
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
        }
    }
}
