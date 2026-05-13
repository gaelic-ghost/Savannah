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

    static func writeState(message: Any?, profileIdentifier: UUID?) -> [String: Any] {
        guard let message = message as? [String: Any] else {
            return [
                "ok": false,
                "error": "SpiderWeb native messaging expected a dictionary payload."
            ]
        }

        guard message["kind"] as? String == "savannah.tabSnapshot" else {
            return [
                "ok": true,
                "handled": false,
                "message": "SpiderWeb received a native message that is not a Savannah tab snapshot."
            ]
        }

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
}
