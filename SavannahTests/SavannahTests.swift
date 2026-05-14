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
