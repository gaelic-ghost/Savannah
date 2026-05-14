//
//  SpiderWebBridgeWriter.swift
//  SpiderWeb
//
//  Created by Codex on 5/13/26.
//

import Foundation

enum SpiderWebBridgeWriter {
    static let appGroupIdentifier = "group.com.galewilliams.Savannah"
    static let stateFileName = "spiderweb-state.json"
    static let commandAcknowledgementsDirectoryName = "spiderweb-command-acks"

    static func writeState(message: Any?, profileIdentifier: UUID?) -> [String: Any] {
        guard let message = message as? [String: Any] else {
            return [
                "ok": false,
                "error": "SpiderWeb native messaging expected a dictionary payload."
            ]
        }

        switch message["kind"] as? String {
        case "savannah.tabSnapshot":
            return writeTabSnapshot(message: message, profileIdentifier: profileIdentifier)
        case "savannah.commandAck":
            return writeCommandAcknowledgement(message: message, profileIdentifier: profileIdentifier)
        default:
            return [
                "ok": true,
                "handled": false,
                "message": "SpiderWeb received a native message that is not a Savannah tab snapshot or command acknowledgement."
            ]
        }
    }

    private static func writeTabSnapshot(message: [String: Any], profileIdentifier: UUID?) -> [String: Any] {
        guard let location = stateLocation() else {
            return [
                "ok": false,
                "handled": true,
                "storage": "missing-app-group",
                "message": "SpiderWeb could not open the shared App Group container. Enable group.com.galewilliams.Savannah on both the app and SpiderWeb targets."
            ]
        }

        var state = message
        state["receivedAt"] = ISO8601DateFormatter().string(from: Date())
        state["profileIdentifier"] = profileIdentifier?.uuidString
        state["storage"] = location.kind

        do {
            try FileManager.default.createDirectory(
                at: location.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(
                withJSONObject: state,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: location.url, options: [.atomic])
            return [
                "ok": true,
                "handled": true,
                "storage": location.kind,
                "path": location.url.path
            ]
        } catch {
            return [
                "ok": false,
                "handled": true,
                "storage": location.kind,
                "path": location.url.path,
                "message": "SpiderWeb could not write the tab snapshot: \(error.localizedDescription)"
            ]
        }
    }

    private static func writeCommandAcknowledgement(
        message: [String: Any],
        profileIdentifier: UUID?
    ) -> [String: Any] {
        guard let requestId = message["requestId"] as? String,
              UUID(uuidString: requestId) != nil
        else {
            return [
                "ok": false,
                "handled": true,
                "message": "SpiderWeb could not write a command acknowledgement because requestId was missing or was not a UUID string."
            ]
        }

        guard let location = commandAcknowledgementLocation(requestId: requestId) else {
            return [
                "ok": false,
                "handled": true,
                "storage": "missing-app-group",
                "message": "SpiderWeb could not open the shared App Group container for command acknowledgements. Enable group.com.galewilliams.Savannah on both the app and SpiderWeb targets."
            ]
        }

        var acknowledgement = message
        acknowledgement["receivedAt"] = ISO8601DateFormatter().string(from: Date())
        acknowledgement["profileIdentifier"] = profileIdentifier?.uuidString
        acknowledgement["storage"] = location.kind

        do {
            try FileManager.default.createDirectory(
                at: location.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(
                withJSONObject: acknowledgement,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: location.url, options: [.atomic])
            return [
                "ok": true,
                "handled": true,
                "storage": location.kind,
                "path": location.url.path,
                "requestId": requestId
            ]
        } catch {
            return [
                "ok": false,
                "handled": true,
                "storage": location.kind,
                "path": location.url.path,
                "message": "SpiderWeb could not write the command acknowledgement: \(error.localizedDescription)"
            ]
        }
    }

    private static func stateLocation() -> (url: URL, kind: String)? {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return (
                groupURL
                    .appendingPathComponent("savannah-codex", isDirectory: true)
                    .appendingPathComponent(stateFileName),
                "app-group"
            )
        }

        let fallbackURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent("savannah-codex", isDirectory: true)
            .appendingPathComponent(stateFileName)
        return (fallbackURL, "extension-container-fallback")
    }

    private static func commandAcknowledgementLocation(requestId: String) -> (url: URL, kind: String)? {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return (
                groupURL
                    .appendingPathComponent("savannah-codex", isDirectory: true)
                    .appendingPathComponent(commandAcknowledgementsDirectoryName, isDirectory: true)
                    .appendingPathComponent("\(requestId).json"),
                "app-group"
            )
        }

        let fallbackURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent("savannah-codex", isDirectory: true)
            .appendingPathComponent(commandAcknowledgementsDirectoryName, isDirectory: true)
            .appendingPathComponent("\(requestId).json")
        return (fallbackURL, "extension-container-fallback")
    }
}
