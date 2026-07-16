import Foundation

public struct SignoffCommandOptions: Sendable {
    private var values: [String: String] = [:]

    public init(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--"),
               index + 1 < arguments.count,
               !arguments[index + 1].hasPrefix("--") {
                values[argument] = arguments[index + 1]
                index += 2
            } else {
                values[argument] = ""
                index += 1
            }
        }
    }

    public func value(_ key: String) -> String? {
        values[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    public func contains(_ key: String) -> Bool {
        values[key] != nil
    }

    public func require(_ key: String) throws -> String {
        guard let value = value(key) else {
            throw SignoffCommand.CLIError(code: 1, message: "missing required \(key)")
        }
        return value
    }

    public func fileURL(_ key: String) throws -> URL {
        let path = try require(key)
        guard FileManager.default.fileExists(atPath: path) else {
            throw SignoffCommand.CLIError(code: 1, message: "\(key) file not found: \(path)")
        }
        return URL(filePath: path)
    }

    public func artifactsDirectory() -> URL {
        if let directory = value("--artifacts") {
            return URL(filePath: directory)
        }
        return FileManager.default.temporaryDirectory.appending(path: "signoff-\(UUID().uuidString)")
    }

    public func replacing(_ key: String, with value: String) -> SignoffCommandOptions {
        var copy = self
        copy.values[key] = value
        return copy
    }
}
