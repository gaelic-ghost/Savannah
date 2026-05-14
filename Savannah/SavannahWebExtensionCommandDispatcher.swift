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
    static let navigateTabURLMessageName = "savannah.navigateTabUrl"
    static let dispatchTimeoutSeconds = 5.0
    static let commandAcknowledgementTimeoutSeconds = 15.0

    static func createTab(params: JSONValue?) -> SavannahCommandDispatchResult {
        dispatch(
            request: WebExtensionCommandRequest(
                kind: "savannah.createTab",
                messageName: createTabMessageName,
                params: params
            ),
            successMessage: "SpiderWeb created a new Safari tab and wrote a command acknowledgement.",
            fallbackFailureMessage: "SpiderWeb reported that Safari did not create the requested tab, but did not include a detailed error message."
        )
    }

    static func navigateTabURL(params: JSONValue?) -> SavannahCommandDispatchResult {
        let request = WebExtensionCommandRequest(
            kind: "savannah.navigateTabUrl",
            messageName: navigateTabURLMessageName,
            params: params
        )

        guard request.payload["tabId"] != nil || request.payload["tab_id"] != nil else {
            return .failure(
                message: "Savannah could not ask SpiderWeb to navigate a Safari tab because tabId was missing.",
                data: baseFailureData(for: request)
            )
        }

        guard request.payload["url"] != nil else {
            return .failure(
                message: "Savannah could not ask SpiderWeb to navigate a Safari tab because url was missing.",
                data: baseFailureData(for: request)
            )
        }

        return dispatch(
            request: request,
            successMessage: "SpiderWeb navigated the Safari tab and wrote a command acknowledgement.",
            fallbackFailureMessage: "SpiderWeb reported that Safari did not navigate the requested tab, but did not include a detailed error message."
        )
    }

    private static func dispatch(
        request: WebExtensionCommandRequest,
        successMessage: String,
        fallbackFailureMessage: String
    ) -> SavannahCommandDispatchResult {
        let dispatch = dispatchMessage(request)
        if let failure = dispatch {
            return failure
        }

        return waitForAcknowledgement(
            request: request,
            successMessage: successMessage,
            fallbackFailureMessage: fallbackFailureMessage
        )
    }

    private static func dispatchMessage(_ request: WebExtensionCommandRequest) -> SavannahCommandDispatchResult? {
        let semaphore = DispatchSemaphore(value: 0)
        let dispatchResult = SafariDispatchResultBox()

        SFSafariApplication.dispatchMessage(
            withName: request.messageName,
            toExtensionWithIdentifier: extensionBundleIdentifier,
            userInfo: request.userInfo
        ) { error in
            dispatchResult.setError(error)
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + dispatchTimeoutSeconds)
        guard waitResult == .success else {
            return .failure(
                message: "Savannah could not ask SpiderWeb to run \(request.kind) because Safari did not acknowledge the extension message within \(Int(dispatchTimeoutSeconds)) seconds.",
                data: baseFailureData(for: request)
            )
        }

        if let dispatchError = dispatchResult.error {
            return .failure(
                message: "Savannah could not ask SpiderWeb to run \(request.kind): \(dispatchError.localizedDescription)",
                data: baseFailureData(for: request)
            )
        }

        return nil
    }

    private static func waitForAcknowledgement(
        request: WebExtensionCommandRequest,
        successMessage: String,
        fallbackFailureMessage: String
    ) -> SavannahCommandDispatchResult {
        switch SavannahExtensionBridgeStore.waitForCommandAcknowledgement(
            requestId: request.requestId,
            timeoutSeconds: commandAcknowledgementTimeoutSeconds
        ) {
        case let .success(acknowledgement):
            guard acknowledgement.ok else {
                return .failure(
                    message: acknowledgement.message
                        ?? acknowledgement.error
                        ?? fallbackFailureMessage,
                    data: baseFailureData(for: request).merging([
                        "acknowledgement": acknowledgement.jsonValue
                    ]) { _, new in new }
                )
            }

            return .success(commandSuccessPayload(
                request: request,
                acknowledgement: acknowledgement,
                message: successMessage
            ))
        case .timeout:
            return .failure(
                message: "Savannah asked SpiderWeb to run \(request.kind), but SpiderWeb did not write a command acknowledgement within \(Int(commandAcknowledgementTimeoutSeconds)) seconds.",
                data: baseFailureData(for: request)
            )
        case let .failure(error):
            return .failure(
                message: error.localizedDescription,
                data: baseFailureData(for: request)
            )
        }
    }

    private static func commandSuccessPayload(
        request: WebExtensionCommandRequest,
        acknowledgement: SpiderWebCommandAcknowledgement,
        message: String
    ) -> [String: JSONValue] {
        var result: [String: JSONValue] = [
            "ok": .bool(true),
            "accepted": .bool(true),
            "completed": .bool(true),
            "capabilitySource": .string("web-extension"),
            "message": .string(message),
            "command": .object(request.payload),
            "acknowledgement": acknowledgement.jsonValue,
            "messageName": .string(request.messageName),
            "extensionBundleIdentifier": .string(extensionBundleIdentifier)
        ]

        if let tab = acknowledgement.tab?.object,
           let id = tab["id"] {
            result["id"] = id
            result["tab"] = .object(tab)
        }

        return result
    }

    private static func baseFailureData(for request: WebExtensionCommandRequest) -> [String: JSONValue] {
        [
            "capabilitySource": .string("web-extension"),
            "messageName": .string(request.messageName),
            "extensionBundleIdentifier": .string(extensionBundleIdentifier),
            "requestId": .string(request.requestId)
        ]
    }
}

nonisolated enum SavannahCommandAcknowledgementWaitResult {
    case success(SpiderWebCommandAcknowledgement)
    case timeout
    case failure(Error)
}

nonisolated struct WebExtensionCommandRequest {
    let kind: String
    let messageName: String
    let requestId: String
    let params: [String: JSONValue]

    init(kind: String, messageName: String, params: JSONValue?) {
        self.kind = kind
        self.messageName = messageName
        requestId = UUID().uuidString
        self.params = params?.object ?? [:]
        SavannahExtensionBridgeStore.removeCommandAcknowledgement(requestId: requestId)
    }

    var payload: [String: JSONValue] {
        var payload: [String: JSONValue] = [
            "kind": .string(kind),
            "protocolVersion": .string(SavannahExtensionBridgeStore.protocolVersion),
            "requestId": .string(requestId)
        ]

        for (key, value) in params {
            payload[key] = value
        }

        return payload
    }

    var userInfo: [String: Any] {
        var userInfo: [String: Any] = [
            "kind": kind,
            "protocolVersion": SavannahExtensionBridgeStore.protocolVersion,
            "requestId": requestId
        ]

        for (key, value) in params {
            userInfo[key] = value.foundationValue
        }

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
