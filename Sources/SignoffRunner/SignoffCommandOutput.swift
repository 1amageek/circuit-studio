import Foundation

public struct SignoffCommandOutput: Sendable {
    private let standardOutputWriter: @Sendable (String) -> Void
    private let standardErrorWriter: @Sendable (String) -> Void

    public init(
        standardOutput: @escaping @Sendable (String) -> Void,
        standardError: @escaping @Sendable (String) -> Void
    ) {
        self.standardOutputWriter = standardOutput
        self.standardErrorWriter = standardError
    }

    public func writeStandardOutput(_ message: String) {
        standardOutputWriter(message)
    }

    public func writeStandardError(_ message: String) {
        standardErrorWriter(message)
    }

    public func writeStandardOutputLine(_ message: String = "") {
        standardOutputWriter("\(message)\n")
    }

    public func writeStandardErrorLine(_ message: String) {
        standardErrorWriter("\(message)\n")
    }

    public static let standard = SignoffCommandOutput(
        standardOutput: { message in
            FileHandle.standardOutput.write(Data(message.utf8))
        },
        standardError: { message in
            FileHandle.standardError.write(Data(message.utf8))
        }
    )
}
