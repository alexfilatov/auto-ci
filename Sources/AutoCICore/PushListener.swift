// Sources/AutoCICore/PushListener.swift
import Foundation

public final class PushListener: @unchecked Sendable {
    public let socketPath: String
    private let onEvent: @Sendable (PushEvent) -> Void
    private var source: DispatchSourceRead?
    private var fd: Int32 = -1

    public init(socketPath: String, onEvent: @escaping @Sendable (PushEvent) -> Void) {
        self.socketPath = socketPath; self.onEvent = onEvent
    }

    public static func decode(_ payload: String) throws -> PushEvent {
        guard let data = payload.data(using: .utf8) else { throw AppError.commandFailed("decode", 1) }
        return try JSONDecoder().decode(PushEvent.self, from: data)
    }

    /// Binds a unix-domain socket and accepts one-shot payloads. Uses `nc -U` clients (see HookInstaller).
    public func start() throws {
        unlink(socketPath)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AppError.commandFailed("socket", errno) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: 104) { strncpy($0, ptr, 103) }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else { throw AppError.commandFailed("bind", errno) }
        guard listen(fd, 8) == 0 else { throw AppError.commandFailed("listen", errno) }

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.resume()
        source = src
    }

    private func acceptOne() {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        var accumulated = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(client, &chunk, chunk.count)
            if n <= 0 { break }
            accumulated.append(contentsOf: chunk[0..<n])
        }
        guard !accumulated.isEmpty else { return }
        let payload = String(decoding: accumulated, as: UTF8.self)
        if let event = try? PushListener.decode(payload) { onEvent(event) }
    }

    public func stop() {
        source?.cancel(); source = nil
        if fd >= 0 { close(fd); fd = -1 }
        unlink(socketPath)
    }
}
