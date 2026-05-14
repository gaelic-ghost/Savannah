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
    static let commandAcknowledgementTimeoutSeconds = 15.0

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

        switch SavannahExtensionBridgeStore.waitForCommandAcknowledgement(
            requestId: request.requestId,
            timeoutSeconds: commandAcknowledgementTimeoutSeconds
        ) {
        case let .success(acknowledgement):
            guard acknowledgement.ok else {
                return .failure(
                    message: acknowledgement.message
                        ?? acknowledgement.error
                        ?? "SpiderWeb reported that Safari did not create the requested tab, but did not include a detailed error message.",
                    data: [
                        "capabilitySource": .string("web-extension"),
                        "messageName": .string(createTabMessageName),
                        "extensionBundleIdentifier": .string(extensionBundleIdentifier),
                        "acknowledgement": acknowledgement.jsonValue
                    ]
                )
            }

            return .success([
                "ok": .bool(true),
                "accepted": .bool(true),
                "completed": .bool(true),
                "capabilitySource": .string("web-extension"),
                "message": .string("SpiderWeb created the Safari tab and wrote a command acknowledgement."),
                "command": .object(request.payload),
                "acknowledgement": acknowledgement.jsonValue,
                "messageName": .string(createTabMessageName),
                "extensionBundleIdentifier": .string(extensionBundleIdentifier)
            ])
        case .timeout:
            return .failure(
                message: "Savannah asked SpiderWeb to create a Safari tab, but SpiderWeb did not write a command acknowledgement within \(Int(commandAcknowledgementTimeoutSeconds)) seconds.",
                data: [
                    "capabilitySource": .string("web-extension"),
                    "messageName": .string(createTabMessageName),
                    "extensionBundleIdentifier": .string(extensionBundleIdentifier),
                    "requestId": .string(request.requestId)
                ]
            )
        case let .failure(error):
            return .failure(
                message: error.localizedDescription,
                data: [
                    "capabilitySource": .string("web-extension"),
                    "messageName": .string(createTabMessageName),
                    "extensionBundleIdentifier": .string(extensionBundleIdentifier),
                    "requestId": .string(request.requestId)
                ]
            )
        }
    }
}

nonisolated enum SavannahCommandAcknowledgementWaitResult {
    case success(SpiderWebCommandAcknowledgement)
    case timeout
    case failure(Error)
}

nonisolated struct CreateTabRequest {
    let requestId: String
    let url: String?
    let active: Bool

    init(params: JSONValue?) {
        let object = params?.object ?? [:]
        requestId = UUID().uuidString
        url = object["url"]?.string
        active = object["active"]?.bool ?? true
        SavannahExtensionBridgeStore.removeCommandAcknowledgement(requestId: requestId)
    }

    var payload: [String: JSONValue] {
        var payload: [String: JSONValue] = [
            "kind": .string("savannah.createTab"),
            "protocolVersion": .string(SavannahExtensionBridgeStore.protocolVersion),
            "requestId": .string(requestId),
            "active": .bool(active)
        ]

        payload["url"] = url.map(JSONValue.string)
        return payload
    }

    var userInfo: [String: Any] {
        var userInfo: [String: Any] = [
            "kind": "savannah.createTab",
            "protocolVersion": SavannahExtensionBridgeStore.protocolVersion,
            "requestId": requestId,
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
