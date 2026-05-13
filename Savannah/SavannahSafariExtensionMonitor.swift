//
//  SavannahSafariExtensionMonitor.swift
//  Savannah
//
//  Created by Codex on 5/13/26.
//

import Foundation
import SafariServices

nonisolated enum SavannahSafariExtensionMonitor {
    static let spiderWebBundleIdentifier = "com.galewilliams.Savannah.SpiderWeb"
    static let safariTourGuideBundleIdentifier = "com.galewilliams.Savannah.SafariTourGuide"

    static func report(timeout: TimeInterval = 1.0) -> SavannahSafariExtensionReport {
        let spiderWeb = statePayload(
            name: "SpiderWeb",
            bundleIdentifier: spiderWebBundleIdentifier,
            timeout: timeout
        )
        let safariTourGuide = statePayload(
            name: "SafariTourGuide",
            bundleIdentifier: safariTourGuideBundleIdentifier,
            timeout: timeout
        )

        return SavannahSafariExtensionReport(
            summary: [
                "spiderWeb": summaryStatus(for: spiderWeb),
                "safariTourGuide": summaryStatus(for: safariTourGuide)
            ],
            details: [
                "spiderWeb": spiderWeb,
                "safariTourGuide": safariTourGuide
            ]
        )
    }

    private static func statePayload(
        name: String,
        bundleIdentifier: String,
        timeout: TimeInterval
    ) -> JSONValue {
        let semaphore = DispatchSemaphore(value: 0)
        let result = SafariExtensionStateResult()

        let completion: @convention(block) (SFSafariExtensionState?, NSError?) -> Void = { state, error in
            if let error {
                result.set(.object([
                    "name": .string(name),
                    "bundleIdentifier": .string(bundleIdentifier),
                    "state": .string("error"),
                    "message": .string(error.localizedDescription)
                ]))
            } else if let state {
                result.set(.object([
                    "name": .string(name),
                    "bundleIdentifier": .string(bundleIdentifier),
                    "state": .string(state.isEnabled ? "enabled" : "disabled"),
                    "isEnabled": .bool(state.isEnabled)
                ]))
            } else {
                result.set(.object([
                    "name": .string(name),
                    "bundleIdentifier": .string(bundleIdentifier),
                    "state": .string("not-found"),
                    "message": .string("Safari did not return state for this bundled extension.")
                ]))
            }
            semaphore.signal()
        }
        let selector = NSSelectorFromString("getStateOfSafariExtensionWithIdentifier:completionHandler:")
        let blockObject = unsafeBitCast(completion, to: AnyObject.self)
        SFSafariExtensionManager.perform(
            selector,
            with: bundleIdentifier as NSString,
            with: blockObject
        )

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            return .object([
                "name": .string(name),
                "bundleIdentifier": .string(bundleIdentifier),
                "state": .string("timeout"),
                "message": .string("Safari did not answer the extension-state request before Savannah's timeout.")
            ])
        }

        return result.value
    }

    private static func summaryStatus(for payload: JSONValue) -> JSONValue {
        payload.object?["state"] ?? .string("unknown")
    }
}

nonisolated struct SavannahSafariExtensionReport {
    let summary: [String: JSONValue]
    let details: [String: JSONValue]
}

nonisolated private final class SafariExtensionStateResult {
    private let lock = NSLock()
    private var storedValue: JSONValue = .object([
        "state": .string("pending")
    ])

    var value: JSONValue {
        lock.lock()
        defer {
            lock.unlock()
        }
        return storedValue
    }

    func set(_ value: JSONValue) {
        lock.lock()
        defer {
            lock.unlock()
        }
        storedValue = value
    }
}

extension SafariExtensionStateResult: @unchecked Sendable {}
