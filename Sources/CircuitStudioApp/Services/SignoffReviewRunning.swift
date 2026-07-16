import Foundation

public struct SignoffAdapterRequest: Sendable, Hashable {
    public let commands: [ExternalSignoffCommand]
    public let replayLogs: [ExternalSignoffLogArtifact]
    public let artifactDirectory: URL

    public init(
        commands: [ExternalSignoffCommand] = [],
        replayLogs: [ExternalSignoffLogArtifact] = [],
        artifactDirectory: URL
    ) {
        self.commands = commands
        self.replayLogs = replayLogs
        self.artifactDirectory = artifactDirectory
    }
}

public protocol SignoffReviewRunning: Sendable {
    var adapterID: String { get }
    func run(request: SignoffAdapterRequest) async throws -> ExternalSignoffReview
}

public enum SignoffAdapterError: Error, LocalizedError, Equatable {
    case emptyCommandSet
    case emptyReplayLogSet
    case unsupportedAdapterID(String)

    public var errorDescription: String? {
        switch self {
        case .emptyCommandSet:
            return "Signoff command adapter requires at least one command."
        case .emptyReplayLogSet:
            return "Signoff replay adapter requires at least one log artifact."
        case .unsupportedAdapterID(let adapterID):
            return "Unsupported signoff adapter ID: \(adapterID)"
        }
    }
}

public struct ExternalCommandSignoffAdapter: SignoffReviewRunning {
    public let adapterID: String
    private let service: ExternalSignoffCommandService

    public init(
        adapterID: String = "generic-command",
        parser: ExternalSignoffReportParser = ExternalSignoffReportParser()
    ) {
        self.adapterID = adapterID
        self.service = ExternalSignoffCommandService(parser: parser)
    }

    public func run(request: SignoffAdapterRequest) async throws -> ExternalSignoffReview {
        guard !request.commands.isEmpty else {
            throw SignoffAdapterError.emptyCommandSet
        }
        return try await service.run(
            commands: request.commands,
            artifactDirectory: request.artifactDirectory
        )
    }
}

public struct GoldenLogReplaySignoffAdapter: SignoffReviewRunning {
    public let adapterID: String
    private let service: ExternalSignoffArtifactService

    public init(
        adapterID: String = "golden-log-replay",
        parser: ExternalSignoffReportParser = ExternalSignoffReportParser()
    ) {
        self.adapterID = adapterID
        self.service = ExternalSignoffArtifactService(parser: parser)
    }

    public func run(request: SignoffAdapterRequest) async throws -> ExternalSignoffReview {
        guard !request.replayLogs.isEmpty else {
            throw SignoffAdapterError.emptyReplayLogSet
        }
        return try service.load(logs: request.replayLogs)
    }
}

public struct SignoffAdapterFactory: Sendable {
    public init() {}

    public func replayAdapter(adapterID: String) throws -> GoldenLogReplaySignoffAdapter {
        try validate(adapterID: adapterID, allowed: [
            "golden-log-replay",
            "calibre-like",
            "magic-netgen-like",
            "klayout-like",
        ])
        return GoldenLogReplaySignoffAdapter(
            adapterID: adapterID,
            parser: parser(adapterID: adapterID)
        )
    }

    public func commandAdapter(adapterID: String = "generic-command") throws -> ExternalCommandSignoffAdapter {
        try validate(adapterID: adapterID, allowed: [
            "generic-command",
            "calibre-like",
            "magic-netgen-like",
            "klayout-like",
        ])
        return ExternalCommandSignoffAdapter(
            adapterID: adapterID,
            parser: parser(adapterID: adapterID)
        )
    }

    public func parser(adapterID: String) -> ExternalSignoffReportParser {
        switch adapterID {
        case "calibre-like", "golden-log-replay":
            return ExternalSignoffReportParser(style: .calibreLike)
        case "magic-netgen-like":
            return ExternalSignoffReportParser(style: .magicNetgenLike)
        case "klayout-like":
            return ExternalSignoffReportParser(style: .klayoutLike)
        default:
            return ExternalSignoffReportParser(style: .generic)
        }
    }

    private func validate(adapterID: String, allowed: Set<String>) throws {
        guard allowed.contains(adapterID) else {
            throw SignoffAdapterError.unsupportedAdapterID(adapterID)
        }
    }
}
