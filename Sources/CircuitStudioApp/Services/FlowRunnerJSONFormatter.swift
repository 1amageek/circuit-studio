import Foundation

public enum FlowRunnerJSONFormatter {
    public static func data(for result: DesignFlowCommandResult) throws -> Data {
        try encodedData(for: result)
    }

    public static func data(for failure: FlowRunnerFailureEnvelope) throws -> Data {
        try encodedData(for: failure)
    }

    public static func string(for result: DesignFlowCommandResult) throws -> String {
        let data = try data(for: result)
        return String(decoding: data, as: UTF8.self)
    }

    public static func string(for failure: FlowRunnerFailureEnvelope) throws -> String {
        let data = try data(for: failure)
        return String(decoding: data, as: UTF8.self)
    }

    private static func encodedData<Value: Encodable>(for value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}
