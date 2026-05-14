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
    static let getTabInfoMessageName = "savannah.getTabInfo"
    static let reloadTabMessageName = "savannah.reloadTab"
    static let closeTabMessageName = "savannah.closeTab"
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
        tabCommand(
            kind: "savannah.navigateTabUrl",
            messageName: navigateTabURLMessageName,
            params: params,
            requiredFields: ["tabId", "url"],
            successMessage: "SpiderWeb navigated the Safari tab and wrote a command acknowledgement.",
            fallbackFailureMessage: "SpiderWeb reported that Safari did not navigate the requested tab, but did not include a detailed error message."
        )
    }

    static func getTabInfo(params: JSONValue?) -> SavannahCommandDispatchResult {
        tabCommand(
            kind: "savannah.getTabInfo",
            messageName: getTabInfoMessageName,
            params: params,
            requiredFields: ["tabId"],
            successMessage: "SpiderWeb read Safari tab information and wrote a command acknowledgement.",
            fallbackFailureMessage: "SpiderWeb reported that Safari did not read the requested tab, but did not include a detailed error message."
        )
    }

    static func reloadTab(params: JSONValue?) -> SavannahCommandDispatchResult {
        tabCommand(
            kind: "savannah.reloadTab",
            messageName: reloadTabMessageName,
            params: params,
            requiredFields: ["tabId"],
            successMessage: "SpiderWeb reloaded the Safari tab and wrote a command acknowledgement.",
            fallbackFailureMessage: "SpiderWeb reported that Safari did not reload the requested tab, but did not include a detailed error message."
        )
    }

    static func closeTab(params: JSONValue?) -> SavannahCommandDispatchResult {
        tabCommand(
            kind: "savannah.closeTab",
            messageName: closeTabMessageName,
            params: params,
            requiredFields: ["tabId"],
            successMessage: "SpiderWeb closed the Safari tab and wrote a command acknowledgement.",
            fallbackFailureMessage: "SpiderWeb reported that Safari did not close the requested tab, but did not include a detailed error message."
        )
    }

    private static func tabCommand(
        kind: String,
        messageName: String,
        params: JSONValue?,
        requiredFields: [String],
        successMessage: String,
        fallbackFailureMessage: String
    ) -> SavannahCommandDispatchResult {
        let request = WebExtensionCommandRequest(
            kind: kind,
            messageName: messageName,
            params: params
        )

        for field in requiredFields where !request.hasField(field) {
            let fieldName = field == "tabId" ? "tabId" : field
            return .failure(
                message: "Savannah could not ask SpiderWeb to run \(kind) because \(fieldName) was missing.",
                data: baseFailureData(for: request)
            )
        }

        return dispatch(
            request: request,
            successMessage: successMessage,
            fallbackFailureMessage: fallbackFailureMessage
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
                message: "Savannah asked SpiderWeb to run \(request.kind), but SpiderWeb did not write a command acknowledgement within \(Int(commandAcknowledgementTimeoutSeconds)) seconds. This usually means Safari has not started or refreshed the SpiderWeb background page; open or activate a Safari tab and retry.",
                data: timeoutFailureData(for: request)
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

    private static func timeoutFailureData(for request: WebExtensionCommandRequest) -> [String: JSONValue] {
        baseFailureData(for: request).merging([
            "webExtensionBridge": SavannahExtensionBridgeStore.loadStatePayload()
        ]) { _, new in new }
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

    func hasField(_ field: String) -> Bool {
        switch field {
        case "tabId":
            return payload["tabId"] != nil || payload["tab_id"] != nil || payload["id"] != nil
        default:
            return payload[field] != nil
        }
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
