//
//  SavannahRPCServer.swift
//  Savannah
//
//  Created by Codex on 5/13/26.
//

import Darwin
import Foundation

nonisolated final class SavannahRPCServer {
    private let queue = DispatchQueue(label: "com.gaelic-ghost.Savannah.rpc-server")
    private let connectionQueue = DispatchQueue(label: "com.gaelic-ghost.Savannah.rpc-connection", attributes: .concurrent)
    private var listenFileDescriptor: Int32 = -1
    private var isRunning = false
    private var router: SavannahCommandRouter?

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        guard isRunning else {
            return
        }
        isRunning = false
        if listenFileDescriptor >= 0 {
            close(listenFileDescriptor)
            listenFileDescriptor = -1
        }
        unlink(SavannahTransportPaths.socketURL.path)
    }

    private func startOnQueue() {
        guard !isRunning else {
            return
        }

        do {
            let token = try SavannahTransportPaths.loadOrCreatePairingToken()
            router = SavannahCommandRouter(pairingToken: token)
            listenFileDescriptor = try makeListeningSocket(path: SavannahTransportPaths.socketURL.path)
            isRunning = true
            acceptNextConnection()
        } catch {
            NSLog("Savannah RPC server failed to start: \(error.localizedDescription)")
        }
    }

    private func acceptNextConnection() {
        queue.async { [weak self] in
            guard let self, self.isRunning else {
                return
            }

            let clientFileDescriptor = accept(self.listenFileDescriptor, nil, nil)
            if clientFileDescriptor >= 0 {
                self.connectionQueue.async { [weak self] in
                    self?.handleConnection(fileDescriptor: clientFileDescriptor)
                }
            } else if self.isRunning {
                NSLog("Savannah RPC server accept failed with errno \(errno): \(String(cString: strerror(errno))).")
            }

            self.acceptNextConnection()
        }
    }

    private func handleConnection(fileDescriptor: Int32) {
        guard let router else {
            close(fileDescriptor)
            return
        }

        var authenticated = false

        while isRunning {
            do {
                let frame = try readFrame(from: fileDescriptor)
                let request = try JSONDecoder().decode(SavannahRPCRequest.self, from: frame)
                let result = router.handle(request, authenticated: authenticated)
                if let authenticatedUpdate = result.authenticated {
                    authenticated = authenticatedUpdate
                }
                let responseData = try JSONEncoder().encode(result.response)
                try writeFrame(responseData, to: fileDescriptor)
            } catch {
                if !(error is EndOfFileError) {
                    NSLog("Savannah RPC server connection ended after read or write failure: \(error.localizedDescription)")
                }
                close(fileDescriptor)
                return
            }
        }

        close(fileDescriptor)
    }
}

extension SavannahRPCServer: @unchecked Sendable {}

nonisolated private func makeListeningSocket(path: String) throws -> Int32 {
    try SavannahTransportPaths.prepareDirectory()
    unlink(path)

    let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fileDescriptor >= 0 else {
        throw POSIXError(.init(rawValue: errno) ?? .EIO)
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
    guard path.utf8.count < maxPathLength else {
        close(fileDescriptor)
        throw SavannahSocketError.pathTooLong(path)
    }

    _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        path.withCString { source in
            strcpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), source)
        }
    }

    let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            bind(fileDescriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard bindResult == 0 else {
        let bindErrno = errno
        close(fileDescriptor)
        throw POSIXError(.init(rawValue: bindErrno) ?? .EIO)
    }

    chmod(path, 0o600)

    guard listen(fileDescriptor, 8) == 0 else {
        let listenErrno = errno
        close(fileDescriptor)
        throw POSIXError(.init(rawValue: listenErrno) ?? .EIO)
    }

    return fileDescriptor
}

nonisolated private func readFrame(from fileDescriptor: Int32) throws -> Data {
    let header = try readExactly(byteCount: 4, from: fileDescriptor)
    let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    guard length > 0, length <= 8 * 1024 * 1024 else {
        throw SavannahSocketError.invalidFrameLength(length)
    }
    return try readExactly(byteCount: Int(length), from: fileDescriptor)
}

nonisolated private func writeFrame(_ data: Data, to fileDescriptor: Int32) throws {
    guard data.count <= 8 * 1024 * 1024 else {
        throw SavannahSocketError.invalidFrameLength(UInt32(data.count))
    }

    let length = UInt32(data.count)
    let header = Data([
        UInt8((length >> 24) & 0xff),
        UInt8((length >> 16) & 0xff),
        UInt8((length >> 8) & 0xff),
        UInt8(length & 0xff)
    ])

    try writeExactly(header + data, to: fileDescriptor)
}

nonisolated private func readExactly(byteCount: Int, from fileDescriptor: Int32) throws -> Data {
    var data = Data(count: byteCount)
    var offset = 0

    while offset < byteCount {
        let bytesRead = data.withUnsafeMutableBytes { buffer in
            read(
                fileDescriptor,
                buffer.baseAddress!.advanced(by: offset),
                byteCount - offset
            )
        }

        if bytesRead == 0 {
            throw EndOfFileError()
        }
        if bytesRead < 0 {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        offset += bytesRead
    }

    return data
}

nonisolated private func writeExactly(_ data: Data, to fileDescriptor: Int32) throws {
    var offset = 0

    while offset < data.count {
        let bytesWritten = data.withUnsafeBytes { buffer in
            write(
                fileDescriptor,
                buffer.baseAddress!.advanced(by: offset),
                data.count - offset
            )
        }

        if bytesWritten < 0 {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        offset += bytesWritten
    }
}

nonisolated private struct EndOfFileError: Error {}

nonisolated private enum SavannahSocketError: Error, LocalizedError {
    case invalidFrameLength(UInt32)
    case pathTooLong(String)

    var errorDescription: String? {
        switch self {
        case let .invalidFrameLength(length):
            "Savannah RPC received an invalid frame length: \(length)."
        case let .pathTooLong(path):
            "Savannah RPC socket path is too long for a Unix domain socket: \(path)."
        }
    }
}
