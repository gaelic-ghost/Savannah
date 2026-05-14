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
    static let commandAcknowledgementsDirectoryName = "spiderweb-command-acks"
    static let protocolVersion = "0.1.0"
    static let snapshotStaleAfterSeconds = 300.0

    static func loadStatePayload(now: Date = Date()) -> JSONValue {
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
            let snapshot = try SpiderWebTabSnapshot.decode(from: data)
            try snapshot.validate(expectedProtocolVersion: protocolVersion)
            return .object([
                "available": .bool(true),
                "storage": .string(location.kind),
                "path": .string(location.url.path),
                "freshness": .object(freshnessPayload(for: snapshot, now: now)),
                "state": snapshot.jsonValue
            ])
        } catch let error as SpiderWebSnapshotValidationError {
            return .object([
                "available": .bool(false),
                "storage": .string(location.kind),
                "path": .string(location.url.path),
                "message": .string(error.localizedDescription)
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

    static func loadTabInventoryPayload(now: Date = Date()) -> [String: JSONValue] {
        let bridge = loadStatePayload(now: now)
        let state = bridge.object?["state"]?.object
        let tabs = state?["tabs"] ?? .array([])
        let hasSnapshot = bridge.object?["available"] == .bool(true)
        let freshness = bridge.object?["freshness"]?.object
        let isFresh = freshness?["isFresh"] == .bool(true)
        let inventory = hasSnapshot
            ? (isFresh ? "web-extension-snapshot" : "web-extension-snapshot-stale")
            : "empty"

        return [
            "tabs": tabs,
            "inventory": .string(inventory),
            "capabilitySource": .string(hasSnapshot ? "web-extension" : "unproven"),
            "webExtensionBridge": bridge,
            "message": .string(
                hasSnapshot
                    ? "Savannah loaded Safari tab inventory from the latest valid SpiderWeb native messaging snapshot."
                    : "Savannah is reachable over its Unix socket, but SpiderWeb has not provided a tab snapshot yet."
            )
        ]
    }

    static func removeCommandAcknowledgement(requestId: String) {
        guard let location = commandAcknowledgementLocation(requestId: requestId) else {
            return
        }

        try? FileManager.default.removeItem(at: location.url)
    }

    static func waitForCommandAcknowledgement(
        requestId: String,
        timeoutSeconds: TimeInterval
    ) -> SavannahCommandAcknowledgementWaitResult {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() <= deadline {
            switch loadCommandAcknowledgement(requestId: requestId) {
            case let .success(acknowledgement):
                removeCommandAcknowledgement(requestId: requestId)
                return .success(acknowledgement)
            case let .failure(error):
                return .failure(error)
            case .none:
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        return .timeout
    }

    private static func freshnessPayload(
        for snapshot: SpiderWebTabSnapshot,
        now: Date
    ) -> [String: JSONValue] {
        guard let capturedAtDate = snapshot.capturedAtDate else {
            return [
                "state": .string("unknown"),
                "isFresh": .bool(false),
                "staleAfterSeconds": .number(snapshotStaleAfterSeconds),
                "message": .string("SpiderWeb snapshot freshness is unknown because capturedAt is not a valid ISO 8601 timestamp.")
            ]
        }

        let ageSeconds = max(0, now.timeIntervalSince(capturedAtDate))
        let isFresh = ageSeconds <= snapshotStaleAfterSeconds

        return [
            "state": .string(isFresh ? "fresh" : "stale"),
            "isFresh": .bool(isFresh),
            "ageSeconds": .number(ageSeconds),
            "staleAfterSeconds": .number(snapshotStaleAfterSeconds)
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

    private static func loadCommandAcknowledgement(
        requestId: String
    ) -> Result<SpiderWebCommandAcknowledgement, Error>? {
        guard let location = commandAcknowledgementLocation(requestId: requestId) else {
            return .failure(SpiderWebCommandAcknowledgementValidationError.missingStorage)
        }

        guard FileManager.default.fileExists(atPath: location.url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: location.url)
            let acknowledgement = try SpiderWebCommandAcknowledgement.decode(from: data)
            try acknowledgement.validate(
                expectedRequestId: requestId,
                expectedProtocolVersion: protocolVersion
            )
            return .success(acknowledgement)
        } catch {
            return .failure(error)
        }
    }

    private static func commandAcknowledgementLocation(
        requestId: String
    ) -> (url: URL, kind: String)? {
        guard UUID(uuidString: requestId) != nil else {
            return nil
        }

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

        return (
            SavannahTransportPaths.runtimeDirectory
                .appendingPathComponent(commandAcknowledgementsDirectoryName, isDirectory: true)
                .appendingPathComponent("\(requestId).json"),
            "app-container-fallback"
        )
    }
}

nonisolated struct SpiderWebTabSnapshot: Decodable, Equatable {
    let kind: String
    let protocolVersion: String
    let reason: String?
    let capturedAt: String
    let receivedAt: String?
    let profileIdentifier: String?
    let storage: String?
    let tabs: [SpiderWebTab]

    var capturedAtDate: Date? {
        Self.parseISO8601Date(capturedAt)
    }

    var jsonValue: JSONValue {
        var object: [String: JSONValue] = [
            "kind": .string(kind),
            "protocolVersion": .string(protocolVersion),
            "capturedAt": .string(capturedAt),
            "tabs": .array(tabs.map(\.jsonValue))
        ]

        object["reason"] = reason.map(JSONValue.string)
        object["receivedAt"] = receivedAt.map(JSONValue.string)
        object["profileIdentifier"] = profileIdentifier.map(JSONValue.string)
        object["storage"] = storage.map(JSONValue.string)

        return .object(object)
    }

    static func decode(from data: Data) throws -> SpiderWebTabSnapshot {
        try JSONDecoder().decode(SpiderWebTabSnapshot.self, from: data)
    }

    func validate(expectedProtocolVersion: String) throws {
        guard kind == "savannah.tabSnapshot" else {
            throw SpiderWebSnapshotValidationError.unexpectedKind(kind)
        }

        guard protocolVersion == expectedProtocolVersion else {
            throw SpiderWebSnapshotValidationError.unsupportedProtocolVersion(
                actual: protocolVersion,
                expected: expectedProtocolVersion
            )
        }
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

nonisolated struct SpiderWebTab: Decodable, Equatable {
    let id: Int?
    let windowId: Int?
    let index: Int?
    let active: Bool?
    let audible: Bool?
    let discarded: Bool?
    let favIconUrl: String?
    let incognito: Bool?
    let pinned: Bool?
    let status: String?
    let title: String?
    let url: String?

    var jsonValue: JSONValue {
        var object: [String: JSONValue] = [:]

        object["id"] = id.map { .number(Double($0)) }
        object["windowId"] = windowId.map { .number(Double($0)) }
        object["index"] = index.map { .number(Double($0)) }
        object["active"] = active.map(JSONValue.bool)
        object["audible"] = audible.map(JSONValue.bool)
        object["discarded"] = discarded.map(JSONValue.bool)
        object["favIconUrl"] = favIconUrl.map(JSONValue.string)
        object["incognito"] = incognito.map(JSONValue.bool)
        object["pinned"] = pinned.map(JSONValue.bool)
        object["status"] = status.map(JSONValue.string)
        object["title"] = title.map(JSONValue.string)
        object["url"] = url.map(JSONValue.string)

        return .object(object)
    }
}

nonisolated enum SpiderWebSnapshotValidationError: Error, LocalizedError, Equatable {
    case unexpectedKind(String)
    case unsupportedProtocolVersion(actual: String, expected: String)

    var errorDescription: String? {
        switch self {
        case let .unexpectedKind(kind):
            "Savannah could not use the SpiderWeb shared state because the snapshot kind was '\(kind)' instead of 'savannah.tabSnapshot'."
        case let .unsupportedProtocolVersion(actual, expected):
            "Savannah could not use the SpiderWeb shared state because the snapshot protocol version was '\(actual)' instead of '\(expected)'."
        }
    }
}

nonisolated struct SpiderWebCommandAcknowledgement: Decodable, Equatable {
    let kind: String
    let protocolVersion: String
    let requestId: String
    let commandKind: String
    let ok: Bool
    let handled: Bool
    let completedAt: String
    let message: String?
    let error: String?
    let tab: JSONValue?
    let snapshotPublish: JSONValue?
    let receivedAt: String?
    let profileIdentifier: String?
    let storage: String?

    var jsonValue: JSONValue {
        var object: [String: JSONValue] = [
            "kind": .string(kind),
            "protocolVersion": .string(protocolVersion),
            "requestId": .string(requestId),
            "commandKind": .string(commandKind),
            "ok": .bool(ok),
            "handled": .bool(handled),
            "completedAt": .string(completedAt)
        ]

        object["message"] = message.map(JSONValue.string)
        object["error"] = error.map(JSONValue.string)
        object["tab"] = tab
        object["snapshotPublish"] = snapshotPublish
        object["receivedAt"] = receivedAt.map(JSONValue.string)
        object["profileIdentifier"] = profileIdentifier.map(JSONValue.string)
        object["storage"] = storage.map(JSONValue.string)

        return .object(object)
    }

    static func decode(from data: Data) throws -> SpiderWebCommandAcknowledgement {
        try JSONDecoder().decode(SpiderWebCommandAcknowledgement.self, from: data)
    }

    func validate(
        expectedRequestId: String,
        expectedProtocolVersion: String
    ) throws {
        guard kind == "savannah.commandAck" else {
            throw SpiderWebCommandAcknowledgementValidationError.unexpectedKind(kind)
        }

        guard protocolVersion == expectedProtocolVersion else {
            throw SpiderWebCommandAcknowledgementValidationError.unsupportedProtocolVersion(
                actual: protocolVersion,
                expected: expectedProtocolVersion
            )
        }

        guard requestId == expectedRequestId else {
            throw SpiderWebCommandAcknowledgementValidationError.unexpectedRequestId(
                actual: requestId,
                expected: expectedRequestId
            )
        }
    }
}

nonisolated enum SpiderWebCommandAcknowledgementValidationError: Error, LocalizedError, Equatable {
    case missingStorage
    case unexpectedKind(String)
    case unsupportedProtocolVersion(actual: String, expected: String)
    case unexpectedRequestId(actual: String, expected: String)

    var errorDescription: String? {
        switch self {
        case .missingStorage:
            "Savannah could not wait for a SpiderWeb command acknowledgement because the App Group storage location was unavailable."
        case let .unexpectedKind(kind):
            "Savannah could not use the SpiderWeb command acknowledgement because the acknowledgement kind was '\(kind)' instead of 'savannah.commandAck'."
        case let .unsupportedProtocolVersion(actual, expected):
            "Savannah could not use the SpiderWeb command acknowledgement because the acknowledgement protocol version was '\(actual)' instead of '\(expected)'."
        case let .unexpectedRequestId(actual, expected):
            "Savannah could not use the SpiderWeb command acknowledgement because the acknowledgement request id was '\(actual)' instead of '\(expected)'."
        }
    }
}
