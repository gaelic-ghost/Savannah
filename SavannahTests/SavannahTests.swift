//
//  SavannahTests.swift
//  SavannahTests
//
//  Created by Gale Williams on 5/12/26.
//

import Foundation
import Testing
@testable import Savannah

struct SavannahTests {

    @Test func spiderWebSnapshotDecodesSupportedTabInventory() throws {
        let data = Data(
            """
            {
              "kind": "savannah.tabSnapshot",
              "protocolVersion": "0.1.0",
              "reason": "tab-updated",
              "capturedAt": "2026-05-13T01:17:59.199Z",
              "tabs": [
                {
                  "id": 653,
                  "windowId": 651,
                  "index": 1,
                  "active": true,
                  "title": "Example Domain",
                  "url": "https://example.com/"
                }
              ]
            }
            """.utf8
        )

        let snapshot = try SpiderWebTabSnapshot.decode(from: data)
        try snapshot.validate(expectedProtocolVersion: "0.1.0")

        #expect(snapshot.kind == "savannah.tabSnapshot")
        #expect(snapshot.protocolVersion == "0.1.0")
        #expect(snapshot.tabs.count == 1)
        #expect(snapshot.tabs.first?.url == "https://example.com/")
        #expect(snapshot.capturedAtDate != nil)
    }

    @Test func spiderWebSnapshotRejectsUnsupportedProtocolVersion() throws {
        let data = Data(
            """
            {
              "kind": "savannah.tabSnapshot",
              "protocolVersion": "9.9.9",
              "capturedAt": "2026-05-13T01:17:59.199Z",
              "tabs": []
            }
            """.utf8
        )

        let snapshot = try SpiderWebTabSnapshot.decode(from: data)

        #expect(throws: SpiderWebSnapshotValidationError.unsupportedProtocolVersion(
            actual: "9.9.9",
            expected: "0.1.0"
        )) {
            try snapshot.validate(expectedProtocolVersion: "0.1.0")
        }
    }

    @Test func spiderWebCommandAcknowledgementDecodesCompletedCreateTab() throws {
        let requestId = "8C2E05F4-3A96-4C3A-8177-239B9BDE25F5"
        let data = Data(
            """
            {
              "kind": "savannah.commandAck",
              "protocolVersion": "0.1.0",
              "requestId": "\(requestId)",
              "commandKind": "savannah.createTab",
              "ok": true,
              "handled": true,
              "completedAt": "2026-05-13T01:17:59.199Z",
              "message": "SpiderWeb created the requested Safari tab.",
              "tab": {
                "id": 2429,
                "active": true,
                "url": "https://example.com/?savannah-create-tab=1"
              },
              "snapshotPublish": {
                "ok": true,
                "handled": true
              }
            }
            """.utf8
        )

        let acknowledgement = try SpiderWebCommandAcknowledgement.decode(from: data)
        try acknowledgement.validate(expectedRequestId: requestId, expectedProtocolVersion: "0.1.0")

        #expect(acknowledgement.ok)
        #expect(acknowledgement.commandKind == "savannah.createTab")
        #expect(acknowledgement.tab?.object?["url"] == .string("https://example.com/?savannah-create-tab=1"))
        #expect(acknowledgement.snapshotPublish?.object?["handled"] == .bool(true))
    }

    @Test func spiderWebCommandAcknowledgementDecodesCompletedNavigation() throws {
        let requestId = "3E1F6DF4-2A72-4459-987B-03BA2B754801"
        let data = Data(
            """
            {
              "kind": "savannah.commandAck",
              "protocolVersion": "0.1.0",
              "requestId": "\(requestId)",
              "commandKind": "savannah.navigateTabUrl",
              "ok": true,
              "handled": true,
              "completedAt": "2026-05-14T18:17:59.199Z",
              "message": "SpiderWeb navigated the requested Safari tab.",
              "tab": {
                "id": 2429,
                "active": true,
                "status": "complete",
                "url": "https://example.com/?savannah-goto=1"
              },
              "snapshotPublish": {
                "ok": true,
                "handled": true
              }
            }
            """.utf8
        )

        let acknowledgement = try SpiderWebCommandAcknowledgement.decode(from: data)
        try acknowledgement.validate(expectedRequestId: requestId, expectedProtocolVersion: "0.1.0")

        #expect(acknowledgement.ok)
        #expect(acknowledgement.commandKind == "savannah.navigateTabUrl")
        #expect(acknowledgement.tab?.object?["status"] == .string("complete"))
        #expect(acknowledgement.tab?.object?["url"] == .string("https://example.com/?savannah-goto=1"))
    }

    @Test func spiderWebCommandAcknowledgementDecodesCompletedCloseWithoutTabPayload() throws {
        let requestId = "5F0EE991-3385-4B8D-86C4-AFC109669EC4"
        let data = Data(
            """
            {
              "kind": "savannah.commandAck",
              "protocolVersion": "0.1.0",
              "requestId": "\(requestId)",
              "commandKind": "savannah.closeTab",
              "ok": true,
              "handled": true,
              "completedAt": "2026-05-14T18:18:59.199Z",
              "message": "SpiderWeb closed the requested Safari tab.",
              "snapshotPublish": {
                "ok": true,
                "handled": true
              }
            }
            """.utf8
        )

        let acknowledgement = try SpiderWebCommandAcknowledgement.decode(from: data)
        try acknowledgement.validate(expectedRequestId: requestId, expectedProtocolVersion: "0.1.0")

        #expect(acknowledgement.ok)
        #expect(acknowledgement.commandKind == "savannah.closeTab")
        #expect(acknowledgement.tab == nil)
        #expect(acknowledgement.snapshotPublish?.object?["handled"] == .bool(true))
    }

    @Test func spiderWebCommandAcknowledgementDecodesCompletedPageSnapshot() throws {
        let requestId = "6C56E0F4-B34B-4FD2-B6ED-67AB63283C80"
        let data = Data(
            """
            {
              "kind": "savannah.commandAck",
              "protocolVersion": "0.1.0",
              "requestId": "\(requestId)",
              "commandKind": "savannah.getPageSnapshot",
              "ok": true,
              "handled": true,
              "completedAt": "2026-05-14T18:19:59.199Z",
              "message": "SpiderWeb read the requested Safari page snapshot.",
              "tab": {
                "id": 2429,
                "active": true,
                "status": "complete",
                "url": "https://example.com/?savannah-page-snapshot=1"
              },
              "pageSnapshot": {
                "kind": "savannah.pageSnapshot",
                "protocolVersion": "0.1.0",
                "title": "Example Domain",
                "url": "https://example.com/?savannah-page-snapshot=1",
                "visibleText": "Example Domain",
                "interactiveElements": []
              }
            }
            """.utf8
        )

        let acknowledgement = try SpiderWebCommandAcknowledgement.decode(from: data)
        try acknowledgement.validate(expectedRequestId: requestId, expectedProtocolVersion: "0.1.0")

        #expect(acknowledgement.ok)
        #expect(acknowledgement.commandKind == "savannah.getPageSnapshot")
        #expect(acknowledgement.pageSnapshot?.object?["title"] == .string("Example Domain"))
        #expect(acknowledgement.jsonValue.object?["pageSnapshot"]?.object?["visibleText"] == .string("Example Domain"))
    }

    @Test func spiderWebCommandAcknowledgementDecodesCompletedDOMCuaAction() throws {
        let requestId = "4372F822-0113-4261-B606-58FB6232A011"
        let data = Data(
            """
            {
              "kind": "savannah.commandAck",
              "protocolVersion": "0.1.0",
              "requestId": "\(requestId)",
              "commandKind": "savannah.domCuaAction",
              "ok": true,
              "handled": true,
              "completedAt": "2026-05-14T18:29:59.199Z",
              "message": "SpiderWeb ran the requested DOM CUA action.",
              "actionResult": {
                "kind": "savannah.domCuaActionResult",
                "protocolVersion": "0.1.0",
                "action": "click",
                "target": {
                  "nodeId": "snapshot-1",
                  "tagName": "a",
                  "selector": "body > div > p > a"
                },
                "url": "https://example.com/"
              },
              "pageSnapshot": {
                "kind": "savannah.pageSnapshot",
                "protocolVersion": "0.1.0",
                "title": "Example Domain",
                "visibleText": "Example Domain"
              }
            }
            """.utf8
        )

        let acknowledgement = try SpiderWebCommandAcknowledgement.decode(from: data)
        try acknowledgement.validate(expectedRequestId: requestId, expectedProtocolVersion: "0.1.0")

        #expect(acknowledgement.ok)
        #expect(acknowledgement.commandKind == "savannah.domCuaAction")
        #expect(acknowledgement.actionResult?.object?["action"] == .string("click"))
        #expect(acknowledgement.jsonValue.object?["actionResult"]?.object?["kind"] == .string("savannah.domCuaActionResult"))
    }

    @Test func spiderWebCommandAcknowledgementRejectsUnexpectedRequestId() throws {
        let data = Data(
            """
            {
              "kind": "savannah.commandAck",
              "protocolVersion": "0.1.0",
              "requestId": "8C2E05F4-3A96-4C3A-8177-239B9BDE25F5",
              "commandKind": "savannah.createTab",
              "ok": true,
              "handled": true,
              "completedAt": "2026-05-13T01:17:59.199Z"
            }
            """.utf8
        )

        let acknowledgement = try SpiderWebCommandAcknowledgement.decode(from: data)

        #expect(throws: SpiderWebCommandAcknowledgementValidationError.unexpectedRequestId(
            actual: "8C2E05F4-3A96-4C3A-8177-239B9BDE25F5",
            expected: "F4F88450-F1D7-4B28-9E42-86D79769F257"
        )) {
            try acknowledgement.validate(
                expectedRequestId: "F4F88450-F1D7-4B28-9E42-86D79769F257",
                expectedProtocolVersion: "0.1.0"
            )
        }
    }

}
