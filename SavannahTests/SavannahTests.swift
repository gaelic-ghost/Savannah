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

}
