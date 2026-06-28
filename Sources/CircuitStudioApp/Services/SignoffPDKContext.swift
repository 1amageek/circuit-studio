import Foundation
import SignoffToolSupport

public enum SignoffPDKContextError: Error, Sendable, Hashable {
    case rootNotFound(profileID: String, requirementID: String)
}

public struct SignoffPDKContext: Sendable, Hashable {
    public static let profilePathEnvironmentKey = "CIRCUIT_STUDIO_SIGNOFF_PDK_PROFILE"
    public static let profileResourceEnvironmentKey = "CIRCUIT_STUDIO_SIGNOFF_PDK_PROFILE_RESOURCE"
    public static let profileCatalogPathEnvironmentKey = "CIRCUIT_STUDIO_SIGNOFF_PDK_PROFILE_CATALOG"
    public static let profileIDEnvironmentKey = "CIRCUIT_STUDIO_SIGNOFF_PDK_PROFILE_ID"

    public let profile: SignoffPDKProfile
    public let pdkRoot: String

    public init(profile: SignoffPDKProfile, pdkRoot: String) {
        self.profile = profile
        self.pdkRoot = pdkRoot
    }

    public static func resolve(
        requirementID: String,
        profile: SignoffPDKProfile? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> SignoffPDKContext {
        let resolvedProfile: SignoffPDKProfile
        if let profile {
            resolvedProfile = profile
        } else {
            resolvedProfile = try loadProfile(environment: environment)
        }

        guard let pdkRoot = SignoffPDKLocator.root(
            requirementID: requirementID,
            profile: resolvedProfile,
            environment: environment,
            fileManager: fileManager
        ) else {
            throw SignoffPDKContextError.rootNotFound(
                profileID: resolvedProfile.profileID,
                requirementID: requirementID
            )
        }
        return SignoffPDKContext(profile: resolvedProfile, pdkRoot: pdkRoot)
    }

    public static func loadProfile(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> SignoffPDKProfile {
        if let profilePath = environment[profilePathEnvironmentKey],
           !profilePath.isEmpty {
            return try SignoffPDKProfile.load(from: URL(filePath: profilePath))
        }
        if let resourceName = environment[profileResourceEnvironmentKey],
           !resourceName.isEmpty {
            return try SignoffPDKProfile.bundledProfile(resourceName: resourceName)
        }
        let profileID = environment[profileIDEnvironmentKey]
        if let catalogPath = environment[profileCatalogPathEnvironmentKey],
           !catalogPath.isEmpty {
            return try SignoffPDKProfileCatalog.load(from: URL(filePath: catalogPath))
                .loadProfile(profileID: profileID)
        }
        return try SignoffPDKProfileCatalog.bundled().loadProfile(profileID: profileID)
    }

    public func requiredFileURL(
        requirementID: String,
        substitutions: [String: String] = [:]
    ) throws -> URL {
        try SignoffPDKLocator.requiredFileURL(
            in: pdkRoot,
            profile: profile,
            requirementID: requirementID,
            substitutions: substitutions
        )
    }
}
