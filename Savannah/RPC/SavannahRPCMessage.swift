//
//  SavannahRPCMessage.swift
//  Savannah
//
//  Created by Codex on 5/13/26.
//

import Foundation

nonisolated struct SavannahRPCRequest: Codable, Equatable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

nonisolated struct SavannahRPCResponse: Codable, Equatable {
    let jsonrpc = "2.0"
    let id: JSONValue?
    let result: JSONValue?
    let error: SavannahRPCError?

    enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case result
        case error
    }

    static func success(id: JSONValue?, result: JSONValue) -> SavannahRPCResponse {
        SavannahRPCResponse(id: id, result: result, error: nil)
    }

    static func failure(id: JSONValue?, code: Int, message: String, data: JSONValue? = nil) -> SavannahRPCResponse {
        SavannahRPCResponse(
            id: id,
            result: nil,
            error: SavannahRPCError(code: code, message: message, data: data)
        )
    }
}

nonisolated struct SavannahRPCError: Codable, Equatable {
    let code: Int
    let message: String
    let data: JSONValue?
}
