//
//  SavannahWebExtensionCommandDispatcher.swift
//  Savannah
//
//  Created by Codex on 5/13/26.
//

import Foundation
import SafariServices

nonisolated enum SavannahWebExtensionCommandDispatcher {
    static let extensionBundleIdentifier = "com.galewilliams.Savannah.SpiderWeb"
    static let createTabMessageName = "savannah.createTab"
    static let dispatchTimeoutSeconds = 5.0

    static func createTab(params: JSONValue?) -> SavannahCommandDispatchResult {
        let request = CreateTabRequest(params: params)
        let userInfo = request.userInfo

        let semaphore = DispatchSemaphore(value: 0)
        let dispatchResult = SafariDispatchResultBox()

        SFSafariApplication.dispatchMessage(
            withName: createTabMessageName,
            toExtensionWithIdentifier: extensionBundleIdentifier,
            userInfo: userInfo
        ) { error in
            dispatchResult.setError(error)
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + dispatchTimeoutSeconds)
        guard waitResult == .success else {
            return .failure(
                message: "Savannah could not ask SpiderWeb to create a Safari tab because Safari did not acknowledge the extension message within \(Int(dispatchTimeoutSeconds)) seconds.",
                data: [
                    "capabilitySource": .string("web-extension"),
                    "messageName": .string(createTabMessageName),
                    "extensionBundleIdentifier": .string(extensionBundleIdentifier)
                ]
            )
        }

        if let dispatchError = dispatchResult.error {
            return .failure(
                message: "Savannah could not ask SpiderWeb to create a Safari tab: \(dispatchError.localizedDescription)",
                data: [
                    "capabilitySource": .string("web-extension"),
                    "messageName": .string(createTabMessageName),
                    "extensionBundleIdentifier": .string(extensionBundleIdentifier)
                ]
            )
        }

        return .success([
            "ok": .bool(true),
            "accepted": .bool(true),
            "capabilitySource": .string("web-extension"),
            "message": .string("Savannah asked SpiderWeb to create a Safari tab. SpiderWeb will publish an updated tab snapshot after Safari applies the request."),
            "command": .object(request.payload),
            "messageName": .string(createTabMessageName),
            "extensionBundleIdentifier": .string(extensionBundleIdentifier)
        ])
    }
}

nonisolated struct CreateTabRequest {
    let url: String?
    let active: Bool

    init(params: JSONValue?) {
        let object = params?.object ?? [:]
        url = object["url"]?.string
        active = object["active"]?.bool ?? true
    }

    var payload: [String: JSONValue] {
        var payload: [String: JSONValue] = [
            "kind": .string("savannah.createTab"),
            "protocolVersion": .string(SavannahExtensionBridgeStore.protocolVersion),
            "active": .bool(active)
        ]

        payload["url"] = url.map(JSONValue.string)
        return payload
    }

    var userInfo: [String: Any] {
        var userInfo: [String: Any] = [
            "kind": "savannah.createTab",
            "protocolVersion": SavannahExtensionBridgeStore.protocolVersion,
            "active": active
        ]

        userInfo["url"] = url
        return userInfo
    }
}

nonisolated enum SavannahCommandDispatchResult {
    case success([String: JSONValue])
    case failure(message: String, data: [String: JSONValue])
}

nonisolated private final class SafariDispatchResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    var error: Error? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return storedError
    }

    func setError(_ error: Error?) {
        lock.lock()
        defer {
            lock.unlock()
        }

        storedError = error
    }
}
