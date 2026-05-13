//
//  SavannahExtensionBridgeStore.swift
//  Savannah
//
//  Created by Codex on 5/13/26.
//

import Foundation

nonisolated enum SavannahExtensionBridgeStore {
    static let appGroupIdentifier = "group.com.galewilliams.Savannah"
    static let stateFileName = "spiderweb-state.json"

    static func loadStatePayload() -> JSONValue {
        guard let location = stateLocation() else {
            return .object([
                "available": .bool(false),
                "storage": .string("missing-app-group"),
                "message": .string("Savannah could not open the SpiderWeb shared state container. Enable the App Group entitlement group.com.galewilliams.Savannah on the app and SpiderWeb targets.")
            ])
        }

        guard FileManager.default.fileExists(atPath: location.url.path) else {
            return .object([
                "available": .bool(false),
                "storage": .string(location.kind),
                "path": .string(location.url.path),
                "message": .string("SpiderWeb has not written a native messaging state snapshot yet.")
            ])
        }

        do {
            let data = try Data(contentsOf: location.url)
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            return .object([
                "available": .bool(true),
                "storage": .string(location.kind),
                "path": .string(location.url.path),
                "state": value
            ])
        } catch {
            return .object([
                "available": .bool(false),
                "storage": .string(location.kind),
                "path": .string(location.url.path),
                "message": .string("Savannah could not read SpiderWeb shared state: \(error.localizedDescription)")
            ])
        }
    }

    static func loadTabInventoryPayload() -> [String: JSONValue] {
        let bridge = loadStatePayload()
        let state = bridge.object?["state"]?.object
        let tabs = state?["tabs"] ?? .array([])
        let hasSnapshot = bridge.object?["available"] == .bool(true)

        return [
            "tabs": tabs,
            "inventory": .string(hasSnapshot ? "web-extension-snapshot" : "empty"),
            "capabilitySource": .string(hasSnapshot ? "web-extension" : "unproven"),
            "webExtensionBridge": bridge,
            "message": .string(
                hasSnapshot
                    ? "Savannah loaded Safari tab inventory from the latest SpiderWeb native messaging snapshot."
                    : "Savannah is reachable over its Unix socket, but SpiderWeb has not provided a tab snapshot yet."
            )
        ]
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

        return (
            SavannahTransportPaths.runtimeDirectory.appendingPathComponent(stateFileName),
            "app-container-fallback"
        )
    }
}
