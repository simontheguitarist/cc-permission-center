import Darwin
import Foundation

protocol SocketServerDelegate: AnyObject {
    func socketServer(_ server: SocketServer,
                      didReceive request: HookRequest,
                      respond: @escaping (HookDecision) -> Void)
}

final class SocketServer: @unchecked Sendable {
    enum ServerError: Error {
        case socketCreate(Int32)
        case bind(Int32)
        case listen(Int32)
        case pathTooLong
    }

    private var listenFd: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "ch.simk.ccpc.accept")
    private let connQueue = DispatchQueue(label: "ch.simk.ccpc.conn", attributes: .concurrent)
    private var acceptSource: DispatchSourceRead?
    weak var delegate: SocketServerDelegate?

    func start(socketPath: String) throws {
        // Ensure parent directory exists.
        let parent = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: parent,
            withIntermediateDirectories: true
        )

        // Remove stale socket if present.
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socketCreate(errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(socketPath.utf8) + [0]
        let pathCap = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= pathCap else {
            close(fd)
            throw ServerError.pathTooLong
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: pathCap) { cstr in
                for (i, b) in pathBytes.enumerated() {
                    cstr[i] = CChar(bitPattern: b)
                }
            }
        }

        let sockLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, sockLen)
            }
        }
        guard bindResult == 0 else {
            let err = errno
            close(fd)
            throw ServerError.bind(err)
        }

        chmod(socketPath, S_IRUSR | S_IWUSR)

        guard Darwin.listen(fd, 8) == 0 else {
            let err = errno
            close(fd)
            throw ServerError.listen(err)
        }

        listenFd = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            self?.acceptOnce()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.listenFd >= 0 {
                close(self.listenFd)
                self.listenFd = -1
            }
        }
        source.resume()
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
    }

    private func acceptOnce() {
        var addr = sockaddr()
        var len = socklen_t(MemoryLayout<sockaddr>.size)
        let clientFd = Darwin.accept(listenFd, &addr, &len)
        guard clientFd >= 0 else { return }
        connQueue.async { [weak self] in
            self?.handleConnection(fd: clientFd)
        }
    }

    private func handleConnection(fd: Int32) {
        defer { close(fd) }

        guard let buffer = readUntilNewline(fd: fd, maxBytes: 1 << 20) else { return }

        let request: HookRequest
        do {
            request = try JSONDecoder().decode(HookRequest.self, from: buffer)
        } catch {
            writeResponse(fd: fd, decision: .ask)
            return
        }

        // Wait synchronously on this queue for the UI to deliver a decision.
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var decided = false
        var decision: HookDecision = .ask

        let respond: (HookDecision) -> Void = { d in
            lock.lock()
            defer { lock.unlock() }
            guard !decided else { return }
            decided = true
            decision = d
            semaphore.signal()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { respond(.ask); return }
            if let delegate = self.delegate {
                delegate.socketServer(self, didReceive: request, respond: respond)
            } else {
                respond(.ask)
            }
        }

        if semaphore.wait(timeout: .now() + .seconds(60)) == .timedOut {
            respond(.ask)
        }

        writeResponse(fd: fd, decision: decision)
    }

    private func readUntilNewline(fd: Int32, maxBytes: Int) -> Data? {
        var buffer = Data()
        let chunkSize = 4096
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        while buffer.count < maxBytes {
            let n = chunk.withUnsafeMutableBufferPointer { ptr -> Int in
                read(fd, ptr.baseAddress, chunkSize)
            }
            if n <= 0 { break }
            buffer.append(chunk, count: n)
            if buffer.last == 0x0a { break }
        }
        return buffer.isEmpty ? nil : buffer
    }

    private func writeResponse(fd: Int32, decision: HookDecision) {
        let response = ["decision": decision.rawValue]
        guard var data = try? JSONSerialization.data(withJSONObject: response) else { return }
        data.append(0x0a)
        data.withUnsafeBytes { ptr in
            _ = Darwin.send(fd, ptr.baseAddress, data.count, 0)
        }
    }
}
