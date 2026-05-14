//
//  JSONValue.swift
//  Savannah
//
//  Created by Codex on 5/13/26.
//

import Foundation

nonisolated enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    var object: [String: JSONValue]? {
        guard case let .object(value) = self else {
            return nil
        }
        return value
    }

    var string: String? {
        guard case let .string(value) = self else {
            return nil
        }
        return value
    }

    var bool: Bool? {
        guard case let .bool(value) = self else {
            return nil
        }
        return value
    }

    var foundationValue: Any {
        switch self {
        case .null:
            return NSNull()
        case let .bool(value):
            return value
        case let .number(value):
            return value
        case let .string(value):
            return value
        case let .array(value):
            return value.map(\.foundationValue)
        case let .object(value):
            return value.mapValues(\.foundationValue)
        }
    }
}
