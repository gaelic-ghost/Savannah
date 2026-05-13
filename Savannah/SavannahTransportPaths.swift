//
//  SavannahTransportPaths.swift
//  Savannah
//
//  Created by Codex on 5/13/26.
//

import Foundation
import Security

nonisolated enum SavannahTransportPaths {
    static let socketFileName = "codex.sock"
    static let tokenFileName = "codex-token"

    static var runtimeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent("savannah-codex", isDirectory: true)
    }

    static var socketURL: URL {
        runtimeDirectory.appendingPathComponent(socketFileName)
    }

    static var tokenURL: URL {
        runtimeDirectory.appendingPathComponent(tokenFileName)
    }

    static func prepareDirectory() throws {
        let directory = runtimeDirectory
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    static func loadOrCreatePairingToken() throws -> String {
        try prepareDirectory()

        if let existing = try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !existing.isEmpty
        {
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw SavannahTransportError.tokenGenerationFailed(status)
        }

        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try token.write(to: tokenURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tokenURL.path
        )
        return token
    }
}

nonisolated enum SavannahTransportError: Error, LocalizedError {
    case tokenGenerationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .tokenGenerationFailed(status):
            "Savannah could not create the Codex pairing token because SecRandomCopyBytes returned status \(status)."
        }
    }
}
