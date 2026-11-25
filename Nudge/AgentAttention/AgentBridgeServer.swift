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
    fileprivate let id = UUID()
    private let ioQueue: DispatchQueue
    private let onFinish: @Sendable (UUID) -> Void
    private var fileDescriptor: Int32
    private var isFinished = false

    fileprivate init(
        fileDescriptor: Int32,
        ioQueue: DispatchQueue,
        onFinish: @escaping @Sendable (UUID) -> Void
    ) {
        self.fileDescriptor = fileDescriptor
        self.ioQueue = ioQueue
        self.onFinish = onFinish
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

    fileprivate var isPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isFinished
    }

    fileprivate func claimPeerDisconnectedFileDescriptor() -> Int32? {
        claimFileDescriptor()
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
        guard !isFinished, fileDescriptor >= 0 else {
            lock.unlock()
            return nil
        }
        isFinished = true
        let descriptor = fileDescriptor
        fileDescriptor = -1
        lock.unlock()
        onFinish(id)
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
    private struct SocketIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    public typealias EventHandler = @MainActor @Sendable (
        AgentEventEnvelope,
        AgentBridgeSession
    ) -> Void
    public typealias DisconnectHandler = @MainActor @Sendable (
        AgentEventEnvelope,
        AgentBridgeSession
    ) -> Void

    private static var runtimeDirectoryPath: String {
        "/tmp/com.nudge.max.agent-\(getuid())"
    }

    public static var socketPath: String {
        "\(runtimeDirectoryPath)/bridge.sock"
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
    private var listeningSocketIdentity: SocketIdentity?
    private var runID: UUID?
    private var sessions: [UUID: AgentBridgeSession] = [:]

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
        let identity = listeningSocketIdentity
        let liveSessions = Array(sessions.values)
        listeningFileDescriptor = -1
        listeningSocketIdentity = nil
        runID = nil
        sessions.removeAll()
        stateLock.unlock()

        liveSessions.forEach { $0.close() }
        controlQueue.async {
            if descriptor >= 0 {
                _ = Darwin.shutdown(descriptor, SHUT_RDWR)
                _ = Darwin.close(descriptor)
            }
            if let identity {
                Self.unlinkOwnedSocket(at: Self.socketPath, matching: identity)
            }
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
        guard Self.ensureOwnedRuntimeDirectory(at: Self.runtimeDirectoryPath) else {
            return
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return }

        var noSigPipe: Int32 = 1
        _ = withUnsafePointer(to: &noSigPipe) {
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }

        guard Self.removeOwnedSocketIfPresent(at: path) else {
            _ = Darwin.close(descriptor)
            return
        }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let sunPathSize = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pathPointer in
            path.withCString { source in
                _ = strlcpy(
                    UnsafeMutableRawPointer(pathPointer).assumingMemoryBound(to: CChar.self),
                    source,
                    sunPathSize
                )
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            _ = Darwin.close(descriptor)
            return
        }

        guard let boundIdentity = Self.socketIdentity(at: path, requiringPrivateMode: false) else {
            _ = Darwin.close(descriptor)
            return
        }
        guard Darwin.chmod(path, 0o600) == 0,
              Self.ownedSocketIdentity(at: path) == boundIdentity,
              Self.isOwnedRuntimeDirectory(at: Self.runtimeDirectoryPath),
              Darwin.listen(descriptor, SOMAXCONN) == 0 else {
            _ = Darwin.close(descriptor)
            Self.unlinkOwnedSocket(at: path, matching: boundIdentity)
            return
        }
        let identity = boundIdentity

        stateLock.lock()
        let shouldRun = self.runID == runID
        if shouldRun {
            listeningFileDescriptor = descriptor
            listeningSocketIdentity = identity
        }
        stateLock.unlock()

        guard shouldRun else {
            _ = Darwin.close(descriptor)
            Self.unlinkOwnedSocket(at: path, matching: identity)
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

            let session = AgentBridgeSession(
                fileDescriptor: client,
                ioQueue: connectionQueue,
                onFinish: { [weak self] sessionID in
                    self?.removeSession(sessionID)
                }
            )
            guard register(session, for: runID) else {
                session.close()
                continue
            }

            connectionQueue.async { [weak self] in
                guard let self else {
                    session.close()
                    return
                }
                self.handleConnection(
                    client,
                    runID: runID,
                    session: session,
                    onEvent: onEvent,
                    onDisconnect: onDisconnect
                )
            }
        }
    }

    private func handleConnection(
        _ descriptor: Int32,
        runID: UUID,
        session: AgentBridgeSession,
        onEvent: @escaping EventHandler,
        onDisconnect: DisconnectHandler?
    ) {
        guard let data = readLine(from: descriptor),
              let envelope = try? JSONDecoder().decode(AgentEventEnvelope.self, from: data),
              envelope.protocolVersion == 1,
              session.isPending else {
            session.close()
            return
        }

        let eventDelivered = DispatchSemaphore(value: 0)
        Task { @MainActor [weak self] in
            defer { eventDelivered.signal() }
            guard let self,
                  session.isPending,
                  isCurrentSession(session, for: runID) else {
                return
            }
            onEvent(envelope, session)
        }
        eventDelivered.wait()

        guard envelope.kind != .completion else {
            session.close()
            return
        }

        guard session.isPending else { return }
        waitForPeerDisconnect(descriptor)
        if let disconnectedDescriptor = session.claimPeerDisconnectedFileDescriptor() {
            Self.closeSocket(disconnectedDescriptor)
            if let onDisconnect {
                Task { @MainActor in
                    onDisconnect(envelope, session)
                }
            }
        }
    }

    private func register(_ session: AgentBridgeSession, for candidateRunID: UUID) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard runID == candidateRunID else { return false }
        sessions[session.id] = session
        return true
    }

    private func removeSession(_ sessionID: UUID) {
        stateLock.lock()
        sessions.removeValue(forKey: sessionID)
        stateLock.unlock()
    }

    private func isCurrentSession(
        _ session: AgentBridgeSession,
        for candidateRunID: UUID
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return runID == candidateRunID && sessions[session.id] === session
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

    private static func removeOwnedSocketIfPresent(at path: String) -> Bool {
        guard path == Self.socketPath else { return false }
        var metadata = stat()
        let result = path.withCString { Darwin.lstat($0, &metadata) }
        if result != 0 {
            return errno == ENOENT
        }
        guard isOwnedSocket(metadata, requiringPrivateMode: true) else { return false }
        return path.withCString { Darwin.unlink($0) } == 0 || errno == ENOENT
    }

    private static func ownedSocketIdentity(at path: String) -> SocketIdentity? {
        socketIdentity(at: path, requiringPrivateMode: true)
    }

    private static func socketIdentity(
        at path: String,
        requiringPrivateMode: Bool
    ) -> SocketIdentity? {
        guard path == Self.socketPath else { return nil }
        var metadata = stat()
        guard path.withCString({ Darwin.lstat($0, &metadata) }) == 0,
              isOwnedSocket(metadata, requiringPrivateMode: requiringPrivateMode) else {
            return nil
        }
        return SocketIdentity(device: metadata.st_dev, inode: metadata.st_ino)
    }

    private static func unlinkOwnedSocket(at path: String, matching identity: SocketIdentity) {
        guard socketIdentity(at: path, requiringPrivateMode: false) == identity else { return }
        path.withCString { pointer in
            _ = Darwin.unlink(pointer)
        }
    }

    private static func ensureOwnedRuntimeDirectory(at path: String) -> Bool {
        guard path == Self.runtimeDirectoryPath else { return false }

        var metadata = stat()
        let existingResult = path.withCString { Darwin.lstat($0, &metadata) }
        if existingResult == 0 {
            return isOwnedRuntimeDirectory(metadata)
        }
        guard errno == ENOENT else { return false }

        let createResult = path.withCString { Darwin.mkdir($0, 0o700) }
        if createResult != 0, errno != EEXIST { return false }
        if createResult == 0, Darwin.chmod(path, 0o700) != 0 { return false }
        return isOwnedRuntimeDirectory(at: path)
    }

    private static func isOwnedRuntimeDirectory(at path: String) -> Bool {
        guard path == Self.runtimeDirectoryPath else { return false }
        var metadata = stat()
        guard path.withCString({ Darwin.lstat($0, &metadata) }) == 0 else {
            return false
        }
        return isOwnedRuntimeDirectory(metadata)
    }

    private static func isOwnedRuntimeDirectory(_ metadata: stat) -> Bool {
        (metadata.st_mode & S_IFMT) == S_IFDIR
            && metadata.st_uid == geteuid()
            && (metadata.st_mode & 0o7777) == 0o700
    }

    private static func isOwnedSocket(
        _ metadata: stat,
        requiringPrivateMode: Bool
    ) -> Bool {
        guard (metadata.st_mode & S_IFMT) == S_IFSOCK,
              metadata.st_uid == geteuid() else {
            return false
        }
        return !requiringPrivateMode || (metadata.st_mode & 0o7777) == 0o600
    }

    private static func closeSocket(_ descriptor: Int32) {
        _ = Darwin.shutdown(descriptor, SHUT_RDWR)
        _ = Darwin.close(descriptor)
    }
}
