import Foundation
import Darwin

public enum AgentBridgeResponse: Equatable, Sendable {
    case answered(answers: [String: String])
    case approvedOnce
    case approvedForSession
    case denied
}

extension AgentBridgeResponse: Encodable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case answers
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .answered(answers):
            try container.encode("answered", forKey: .kind)
            try container.encode(answers, forKey: .answers)
        case .approvedOnce:
            try container.encode("approvedOnce", forKey: .kind)
        case .approvedForSession:
            try container.encode("approvedForSession", forKey: .kind)
        case .denied:
            try container.encode("denied", forKey: .kind)
        }
    }
}

public final class AgentBridgeSession: @unchecked Sendable {
    private struct Handoff: Encodable {
        let kind = "handoff"
    }

    private let lock = NSLock()
    private let ioQueue: DispatchQueue
    private var fileDescriptor: Int32
    private var isFinished = false

    fileprivate init(fileDescriptor: Int32, ioQueue: DispatchQueue) {
        self.fileDescriptor = fileDescriptor
        self.ioQueue = ioQueue
    }

    public func respond(_ response: AgentBridgeResponse) {
        guard let data = try? JSONEncoder().encode(response) else {
            close()
            return
        }
        finish(with: data)
    }

    public func handoff() {
        guard let data = try? JSONEncoder().encode(Handoff()) else {
            close()
            return
        }
        finish(with: data)
    }

    public func close() {
        guard let descriptor = claimFileDescriptor() else { return }
        ioQueue.async {
            Self.closeSocket(descriptor)
        }
    }

    fileprivate func markPeerDisconnected() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return false }
        isFinished = true
        fileDescriptor = -1
        return true
    }

    private func finish(with response: Data) {
        guard let descriptor = claimFileDescriptor() else { return }
        var line = response
        line.append(0x0A)
        let lineData = line
        ioQueue.async {
            _ = Self.writeAll(lineData, to: descriptor)
            Self.closeSocket(descriptor)
        }
    }

    private func claimFileDescriptor() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, fileDescriptor >= 0 else { return nil }
        isFinished = true
        let descriptor = fileDescriptor
        fileDescriptor = -1
        return descriptor
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return true }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    private static func closeSocket(_ descriptor: Int32) {
        _ = Darwin.shutdown(descriptor, SHUT_RDWR)
        _ = Darwin.close(descriptor)
    }
}

public final class AgentBridgeServer: @unchecked Sendable {
    public typealias EventHandler = @MainActor @Sendable (
        AgentEventEnvelope,
        AgentBridgeSession
    ) -> Void
    public typealias DisconnectHandler = @MainActor @Sendable (
        AgentEventEnvelope,
        AgentBridgeSession
    ) -> Void

    public static var socketPath: String {
        "/tmp/com.nudge.max.agent-\(getuid()).sock"
    }

    private static let maximumLineBytes = 1024 * 1024

    private let stateLock = NSLock()
    private let controlQueue = DispatchQueue(
        label: "com.nudge.max.agent-bridge.control",
        qos: .utility
    )
    private let connectionQueue = DispatchQueue(
        label: "com.nudge.max.agent-bridge.connections",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var listeningFileDescriptor: Int32 = -1
    private var runID: UUID?

    public init() {}

    deinit {
        stop()
    }

    public func start(
        onEvent: @escaping EventHandler,
        onDisconnect: DisconnectHandler? = nil
    ) {
        stop()
        let newRunID = UUID()
        stateLock.lock()
        runID = newRunID
        stateLock.unlock()

        controlQueue.async { [weak self] in
            self?.openSocketAndAccept(
                runID: newRunID,
                onEvent: onEvent,
                onDisconnect: onDisconnect
            )
        }
    }

    public func stop() {
        stateLock.lock()
        let descriptor = listeningFileDescriptor
        listeningFileDescriptor = -1
        runID = nil
        stateLock.unlock()

        controlQueue.async {
            if descriptor >= 0 {
                _ = Darwin.shutdown(descriptor, SHUT_RDWR)
                _ = Darwin.close(descriptor)
            }
            Self.unlinkExactSocketPath(Self.socketPath)
        }
    }

    private func openSocketAndAccept(
        runID: UUID,
        onEvent: @escaping EventHandler,
        onDisconnect: DisconnectHandler?
    ) {
        let path = Self.socketPath
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            return
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return }

        var noSigPipe: Int32 = 1
        _ = withUnsafePointer(to: &noSigPipe) {
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }

        Self.unlinkExactSocketPath(path)

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pathPointer in
            path.withCString { source in
                _ = strlcpy(
                    UnsafeMutableRawPointer(pathPointer).assumingMemoryBound(to: CChar.self),
                    source,
                    MemoryLayout.size(ofValue: address.sun_path)
                )
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0,
              Darwin.chmod(path, 0o600) == 0,
              Darwin.listen(descriptor, SOMAXCONN) == 0 else {
            _ = Darwin.close(descriptor)
            Self.unlinkExactSocketPath(path)
            return
        }

        stateLock.lock()
        let shouldRun = self.runID == runID
        if shouldRun {
            listeningFileDescriptor = descriptor
        }
        stateLock.unlock()

        guard shouldRun else {
            _ = Darwin.close(descriptor)
            Self.unlinkExactSocketPath(path)
            return
        }

        connectionQueue.async { [weak self] in
            self?.acceptConnections(
                descriptor: descriptor,
                runID: runID,
                onEvent: onEvent,
                onDisconnect: onDisconnect
            )
        }
    }

    private func acceptConnections(
        descriptor: Int32,
        runID: UUID,
        onEvent: @escaping EventHandler,
        onDisconnect: DisconnectHandler?
    ) {
        while isCurrentRun(runID, descriptor: descriptor) {
            let client = Darwin.accept(descriptor, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }

            var noSigPipe: Int32 = 1
            _ = withUnsafePointer(to: &noSigPipe) {
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
            }

            connectionQueue.async { [weak self] in
                guard let self else {
                    AgentBridgeServer.closeSocket(client)
                    return
                }
                self.handleConnection(client, onEvent: onEvent, onDisconnect: onDisconnect)
            }
        }
    }

    private func handleConnection(
        _ descriptor: Int32,
        onEvent: @escaping EventHandler,
        onDisconnect: DisconnectHandler?
    ) {
        guard let data = readLine(from: descriptor),
              let envelope = try? JSONDecoder().decode(AgentEventEnvelope.self, from: data),
              envelope.protocolVersion == 1 else {
            Self.closeSocket(descriptor)
            return
        }

        let session = AgentBridgeSession(
            fileDescriptor: descriptor,
            ioQueue: connectionQueue
        )
        Task { @MainActor in
            onEvent(envelope, session)
        }

        guard envelope.kind != .completion else {
            session.close()
            return
        }

        waitForPeerDisconnect(descriptor)
        if session.markPeerDisconnected() {
            Self.closeSocket(descriptor)
            if let onDisconnect {
                Task { @MainActor in
                    onDisconnect(envelope, session)
                }
            }
        }
    }

    private func readLine(from descriptor: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)

        while data.count <= Self.maximumLineBytes {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                if let newline = buffer[..<count].firstIndex(of: 0x0A) {
                    data.append(contentsOf: buffer[..<newline])
                    guard data.count <= Self.maximumLineBytes,
                          String(data: data, encoding: .utf8) != nil else {
                        return nil
                    }
                    return data
                }
                data.append(contentsOf: buffer[..<count])
            } else if count == 0 {
                return nil
            } else if errno == EINTR {
                continue
            } else {
                return nil
            }
        }
        return nil
    }

    private func waitForPeerDisconnect(_ descriptor: Int32) {
        var byte: UInt8 = 0
        while true {
            let count = Darwin.read(descriptor, &byte, 1)
            if count == 0 { return }
            if count < 0, errno == EINTR { continue }
            if count < 0 { return }
        }
    }

    private func isCurrentRun(_ candidate: UUID, descriptor: Int32) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return runID == candidate && listeningFileDescriptor == descriptor
    }

    private static func unlinkExactSocketPath(_ path: String) {
        guard path == Self.socketPath else { return }
        path.withCString { pointer in
            _ = Darwin.unlink(pointer)
        }
    }

    private static func closeSocket(_ descriptor: Int32) {
        _ = Darwin.shutdown(descriptor, SHUT_RDWR)
        _ = Darwin.close(descriptor)
    }
}
