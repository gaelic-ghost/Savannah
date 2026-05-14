//
//  SavannahCommandRouter.swift
//  Savannah
//
//  Created by Codex on 5/13/26.
//

import Foundation

nonisolated final class SavannahCommandRouter {
    private let pairingToken: String
    private let stateLock = NSLock()
    private var sessionName: String?

    init(pairingToken: String) {
        self.pairingToken = pairingToken
    }

    func handle(_ request: SavannahRPCRequest, authenticated: Bool) -> CommandResult {
        if request.method == "hello" {
            return authenticate(request)
        }

        guard authenticated else {
            return CommandResult(
                authenticated: false,
                response: .failure(
                    id: request.id,
                    code: -32001,
                    message: "Savannah rejected the Codex plugin command because the connection has not completed the hello handshake."
                )
            )
        }

        switch request.method {
        case "ping":
            return success(request, result: [
                "ok": .bool(true),
                "result": .string("pong"),
                "backendId": .string("savannah"),
                "transport": .string("unix-socket-json-rpc")
            ])
        case "getInfo":
            return success(request, result: infoPayload())
        case "nameSession":
            let sessionName = updateSessionName(request.params?.object?["name"]?.string)
            return success(request, result: [
                "ok": .bool(true),
                "sessionName": .string(sessionName)
            ])
        case "getTabs", "getUserTabs":
            return success(request, result: SavannahExtensionBridgeStore.loadTabInventoryPayload())
        case "createTab":
            return handleCreateTab(request, authenticated: authenticated)
        case "navigateTabUrl", "navigate_tab_url":
            return handleNavigateTabURL(request, authenticated: authenticated)
        case "finalizeTabs":
            return success(request, result: [
                "ok": .bool(true),
                "backendId": .string("savannah")
            ])
        default:
            return CommandResult(
                authenticated: authenticated,
                response: .failure(
                    id: request.id,
                    code: -32601,
                    message: "Savannah does not implement JSON-RPC method '\(request.method)' yet.",
                    data: .object([
                        "method": .string(request.method),
                        "capabilitySource": .string("unsupported")
                    ])
                )
            )
        }
    }

    private func authenticate(_ request: SavannahRPCRequest) -> CommandResult {
        let params = request.params?.object
        let token = params?["token"]?.string
        let protocolVersion = params?["protocolVersion"]?.string

        guard protocolVersion == "0.1.0" else {
            return CommandResult(
                authenticated: false,
                response: .failure(
                    id: request.id,
                    code: -32002,
                    message: "Savannah rejected the Codex plugin handshake because the protocol version is unsupported.",
                    data: .object(["expectedProtocolVersion": .string("0.1.0")])
                )
            )
        }

        guard token == pairingToken else {
            return CommandResult(
                authenticated: false,
                response: .failure(
                    id: request.id,
                    code: -32003,
                    message: "Savannah rejected the Codex plugin handshake because the pairing token did not match."
                )
            )
        }

        return success(request, authenticated: true, result: [
            "ok": .bool(true),
            "backendId": .string("savannah"),
            "protocolVersion": .string("0.1.0"),
            "transport": .string("unix-socket-json-rpc")
        ])
    }

    private func updateSessionName(_ name: String?) -> String {
        stateLock.lock()
        defer {
            stateLock.unlock()
        }

        sessionName = name
        return sessionName ?? ""
    }

    private func infoPayload() -> [String: JSONValue] {
        let safariExtensions = SavannahSafariExtensionMonitor.report()
        let webExtensionBridge = SavannahExtensionBridgeStore.loadStatePayload()
        let tabCapabilitySource = webExtensionBridge.object?["available"] == .bool(true)
            ? JSONValue.string("web-extension")
            : JSONValue.string("unproven")

        return [
            "backendId": .string("savannah"),
            "backendKind": .string("chrome-compatible-proof"),
            "protocolVersion": .string("0.1.0"),
            "transport": .object([
                "kind": .string("unix-socket-json-rpc"),
                "socketPath": .string(SavannahTransportPaths.socketURL.path),
                "authenticated": .bool(true)
            ]),
            "extensions": .object(safariExtensions.summary),
            "safariExtensionStates": .object(safariExtensions.details),
            "webExtensionBridge": webExtensionBridge,
            "capabilitySources": .object([
                "ping": .string("app"),
                "getInfo": .string("app"),
                "getTabs": tabCapabilitySource,
                "getUserTabs": tabCapabilitySource,
                "getUserHistory": .string("unsupported"),
                "claimUserTab": .string("unproven"),
                "createTab": .string("web-extension"),
                "navigateTabUrl": .string("web-extension"),
                "navigate_tab_url": .string("web-extension"),
                "finalizeTabs": .string("app"),
                "nameSession": .string("app"),
                "attach": .string("unproven"),
                "detach": .string("unproven"),
                "executeCdp": .string("unsupported"),
                "executeUnhandledCommand": .string("app"),
                "moveMouse": .string("unproven")
            ])
        ]
    }

    private func success(
        _ request: SavannahRPCRequest,
        authenticated: Bool? = nil,
        result: [String: JSONValue]
    ) -> CommandResult {
        CommandResult(
            authenticated: authenticated,
            response: .success(id: request.id, result: .object(result))
        )
    }

    private func handleCreateTab(_ request: SavannahRPCRequest, authenticated: Bool) -> CommandResult {
        switch SavannahWebExtensionCommandDispatcher.createTab(params: request.params) {
        case let .success(result):
            return success(request, result: result)
        case let .failure(message, data):
            return CommandResult(
                authenticated: authenticated,
                response: .failure(
                    id: request.id,
                    code: -32010,
                    message: message,
                    data: .object(data)
                )
            )
        }
    }

    private func handleNavigateTabURL(_ request: SavannahRPCRequest, authenticated: Bool) -> CommandResult {
        switch SavannahWebExtensionCommandDispatcher.navigateTabURL(params: request.params) {
        case let .success(result):
            return success(request, result: result)
        case let .failure(message, data):
            return CommandResult(
                authenticated: authenticated,
                response: .failure(
                    id: request.id,
                    code: -32011,
                    message: message,
                    data: .object(data)
                )
            )
        }
    }
}

nonisolated struct CommandResult {
    let authenticated: Bool?
    let response: SavannahRPCResponse
}
