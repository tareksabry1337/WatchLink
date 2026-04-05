import Foundation
import WatchConnectivity
import WatchLinkCore

public actor WCTransport: Transport {
    private let session: any WCSessionProtocol
    private var incomingContinuation: AsyncStream<Data>.Continuation?
    private var reachabilityContinuation: AsyncStream<Bool>.Continuation?

    public var isReachable: Bool {
        session.isActivatedAndReachable
    }

    public var reachabilityChanges: AsyncStream<Bool> {
        AsyncStream { continuation in
            reachabilityContinuation = continuation
        }
    }

    public init(session: any WCSessionProtocol) {
        self.session = session
    }

    public func start() async {
        session.activate()
    }

    public func stop() async {
        incomingContinuation?.finish()
        incomingContinuation = nil
        reachabilityContinuation?.finish()
        reachabilityContinuation = nil
    }

    public func send(_ data: Data) async throws {
        guard isReachable else {
            throw WatchLinkError.sendFailed("WCSession not reachable")
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.sendMessageData(data, replyHandler: { _ in
                cont.resume()
            }, errorHandler: { error in
                cont.resume(throwing: WatchLinkError.sendFailed(error.localizedDescription))
            })
        }
    }

    public func incoming() -> AsyncStream<Data> {
        AsyncStream { continuation in
            incomingContinuation = continuation
        }
    }

    func handleIncoming(_ data: Data) {
        incomingContinuation?.yield(data)
    }

    func handleReachabilityChanged(_ reachable: Bool) {
        reachabilityContinuation?.yield(reachable)
    }
}

extension WCSession: WCSessionProtocol {
    public var isActivatedAndReachable: Bool {
        activationState == .activated && isReachable
    }
}

public final class WCSessionBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    private weak var transport: WCTransport?

    public init(transport: WCTransport, session: WCSession = .default) {
        self.transport = transport
        super.init()
        session.delegate = self
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { [weak transport] in
            await transport?.handleReachabilityChanged(reachable)
        }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    public func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { [weak transport] in
            await transport?.handleReachabilityChanged(reachable)
        }
    }

    public func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { [weak transport] in
            await transport?.handleIncoming(messageData)
        }
    }

    public func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        Task { [weak transport] in
            await transport?.handleIncoming(messageData)
        }
        replyHandler(Data())
    }
}
