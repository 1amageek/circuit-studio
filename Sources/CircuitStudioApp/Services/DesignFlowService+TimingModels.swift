import Foundation
import CircuitPhysicalDesign
import DesignFlowKernel

extension DesignFlowService {
    func inspectTimingModelProfiles(_ command: DesignFlowCommand) throws -> DesignFlowCommandResult {
        if command.timingModelProfilePath != nil {
            throw DesignFlowCommandError.conflictingTimingModelProfileSelectors
        }
        let catalogURL = command.timingModelProfileCatalogPath.map { URL(filePath: $0) }
        let catalog = try catalogURL.map { try TimingModelProfileCatalog.load(from: $0) }
            ?? TimingModelProfileCatalog.bundled()
        let selectedEntry = try catalog.entry(
            profileID: command.timingModelProfileID,
            cornerID: command.timingModelCornerID
        )
        let inspection = TimingModelProfileCatalogInspection(
            catalogID: catalog.catalogID,
            catalogPath: catalogURL?.path(percentEncoded: false),
            profiles: catalog.profiles.map {
                timingModelProfileInspection(for: $0, catalogURL: catalogURL)
            }
        )
        return DesignFlowCommandResult(
            kind: command.kind,
            timingModelProfileID: selectedEntry.profileID,
            timingModelProfileCatalogID: catalog.catalogID,
            timingModelProfileCatalogPath: catalogURL?.path(percentEncoded: false),
            timingModelProfileCatalogInspection: inspection,
            timingModelCornerID: selectedEntry.cornerID
        )
    }

    @MainActor
    func buildTimingLibrary(_ command: DesignFlowCommand) async throws -> DesignFlowCommandResult {
        guard let projectRootPath = command.projectRootPath else {
            throw DesignFlowCommandError.missingProjectRoot
        }
        let runID = command.runID ?? "timing-library-\(Self.timestamp())"
        try HeadlessRoundTripService.validateRunID(runID)

        let projectRoot = URL(filePath: projectRootPath)
        let runDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let profile = try timingModelProfile(for: command)
        let profileSelection = TimingModelProfileSelection(
            runID: runID,
            sourceKind: profile.sourceKind,
            selectionReason: profile.selectionReason,
            catalogID: profile.catalogID,
            catalogPath: profile.catalogPath,
            profileSchemaVersion: profile.profile.schemaVersion,
            profile: profile.technologyContext.modelProfile ?? TimingModelProfileReference(
                profileID: profile.profile.profileID
            ),
            technology: profile.technologyContext
        )
        let timingBuild = try await StandardTimingLibraryBuilder(
            model: profile.profile.model,
            technologyContext: profile.technologyContext
        ).buildStandardLibrary(runID: runID)
        let writeResult = try TimingArtifactWriter().write(
            runID: runID,
            runDirectory: runDirectory,
            technology: timingBuild.sequentialReport.technology,
            library: timingBuild.libraryArtifact,
            profileSelection: profileSelection,
            staReport: nil,
            combinationalReport: timingBuild.combinationalReport,
            sequentialReport: timingBuild.sequentialReport,
            validationReports: [],
            claims: [
                TimingArtifactManifest.Claim(
                    statement: "standard timing library is SPICE-characterized",
                    passed: timingBuild.combinationalReport.status == .passed
                        && timingBuild.sequentialReport.status == .passed,
                    artifactIDs: [
                        "timing-library",
                        "timing-model-profile-selection",
                        "combinational-characterization",
                        "sequential-dff-characterization",
                    ]
                ),
            ]
        )
        let libraryPath = writeResult.record(id: "timing-library").map {
            runDirectory.appending(path: $0.path).path(percentEncoded: false)
        }
        let selectionPath = writeResult.record(id: "timing-model-profile-selection").map {
            runDirectory.appending(path: $0.path).path(percentEncoded: false)
        }

        return DesignFlowCommandResult(
            kind: command.kind,
            runID: runID,
            projectRootPath: projectRoot.path(percentEncoded: false),
            timingArtifactManifestPath: writeResult.manifestURL.path(percentEncoded: false),
            timingLibraryPath: libraryPath,
            timingModelProfileSelectionPath: selectionPath,
            timingModelProfileID: profile.profile.profileID,
            timingModelProfilePath: profile.profilePath,
            timingModelProfileCatalogID: profile.catalogID,
            timingModelProfileCatalogPath: profile.catalogPath,
            timingModelCornerID: profile.technologyContext.cornerID
        )
    }

    private func timingModelProfile(
        for command: DesignFlowCommand
    ) throws -> (
        profile: Level1DeviceModelProfile,
        technologyContext: TimingTechnologyContext,
        profilePath: String?,
        catalogID: String?,
        catalogPath: String?,
        sourceKind: TimingModelProfileSelection.SourceKind,
        selectionReason: String
    ) {
        if let profilePath = command.timingModelProfilePath {
            if command.timingModelProfileCatalogPath != nil
                || command.timingModelProfileID != nil
                || command.timingModelCornerID != nil {
                throw DesignFlowCommandError.conflictingTimingModelProfileSelectors
            }
            let profileURL = URL(filePath: profilePath)
            let profile = try Level1DeviceModelProfile.load(from: profileURL)
            let digest = try RoundTripArtifactDigest.compute(url: profileURL)
            return (
                profile,
                try profile.technologyContext(
                    path: profileURL.path(percentEncoded: false),
                    sha256: digest.sha256
                ),
                profileURL.path(percentEncoded: false),
                nil,
                nil,
                .externalFile,
                "explicit timing model profile path"
            )
        }

        let catalogURL = command.timingModelProfileCatalogPath.map { URL(filePath: $0) }
        let catalog = try catalogURL.map { try TimingModelProfileCatalog.load(from: $0) }
            ?? TimingModelProfileCatalog.bundled()
        let catalogEntry = try catalog.entry(
            profileID: command.timingModelProfileID,
            cornerID: command.timingModelCornerID
        )
        let catalogPath = catalogURL?.path(percentEncoded: false)

        if let resourceName = catalogEntry.profileResourceName {
            let profile = try Level1DeviceModelProfile.bundled(resourceName: resourceName)
            guard profile.profileID == catalogEntry.profileID else {
                throw DesignFlowCommandError.timingModelProfileCatalogEntryMismatch(
                    expected: catalogEntry.profileID,
                    actual: profile.profileID
                )
            }
            try validateCatalogCorner(entry: catalogEntry, profile: profile)
            return (
                profile,
                try profile.technologyContext(resourceName: resourceName),
                nil,
                catalog.catalogID,
                catalogPath,
                .bundledResource,
                "catalog timing model profile selection"
            )
        }

        let profilePath = try resolvedProfilePath(from: catalogEntry, catalogURL: catalogURL)
        let profile = try Level1DeviceModelProfile.load(from: profilePath)
        guard profile.profileID == catalogEntry.profileID else {
            throw DesignFlowCommandError.timingModelProfileCatalogEntryMismatch(
                expected: catalogEntry.profileID,
                actual: profile.profileID
            )
        }
        try validateCatalogCorner(entry: catalogEntry, profile: profile)
        let digest = try RoundTripArtifactDigest.compute(url: profilePath)
        return (
            profile,
            try profile.technologyContext(
                path: profilePath.path(percentEncoded: false),
                sha256: digest.sha256
            ),
            profilePath.path(percentEncoded: false),
            catalog.catalogID,
            catalogPath,
            .externalFile,
            "catalog timing model profile selection"
        )
    }

    private func validateCatalogCorner(
        entry: TimingModelProfileCatalog.Entry,
        profile: Level1DeviceModelProfile
    ) throws {
        guard let declaredCornerID = entry.cornerID else {
            return
        }
        guard declaredCornerID == profile.technology.cornerID else {
            throw DesignFlowCommandError.timingModelProfileCatalogCornerMismatch(
                profileID: entry.profileID,
                declared: declaredCornerID,
                actual: profile.technology.cornerID
            )
        }
    }

    private func resolvedProfilePath(
        from entry: TimingModelProfileCatalog.Entry,
        catalogURL: URL?
    ) throws -> URL {
        guard let profilePath = entry.profilePath else {
            throw TimingModelProfileCatalogError.missingProfileReference(entry.profileID)
        }
        if profilePath.hasPrefix("/") {
            return URL(filePath: profilePath)
        }
        if let catalogURL {
            return catalogURL.deletingLastPathComponent().appending(path: profilePath)
        }
        return URL(filePath: profilePath)
    }

    private func timingModelProfileInspection(
        for entry: TimingModelProfileCatalog.Entry,
        catalogURL: URL?
    ) -> TimingModelProfileCatalogInspection.Profile {
        let sourceKind: TimingModelProfileSelection.SourceKind = entry.profileResourceName == nil
            ? .externalFile
            : .bundledResource
        let resolvedPath: String?
        let profileURL: URL

        do {
            if let resourceName = entry.profileResourceName {
                profileURL = try bundledTimingModelProfileURL(resourceName: resourceName)
                resolvedPath = nil
            } else {
                profileURL = try resolvedProfilePath(from: entry, catalogURL: catalogURL)
                resolvedPath = profileURL.path(percentEncoded: false)
            }
        } catch {
            return failedTimingModelProfileInspection(
                for: entry,
                sourceKind: sourceKind,
                profilePath: nil,
                code: "profile-reference-unresolved",
                error: error
            )
        }

        do {
            let profile = try Level1DeviceModelProfile.load(from: profileURL)
            let digest = try RoundTripArtifactDigest.compute(url: profileURL)
            let modelHash = try TimingTopologyHasher.hashModel(profile.model)
            var diagnostics: [TimingModelProfileCatalogInspection.Diagnostic] = []
            if profile.profileID != entry.profileID {
                diagnostics.append(TimingModelProfileCatalogInspection.Diagnostic(
                    severity: "error",
                    code: "profile-id-mismatch",
                    message: "Catalog entry '\(entry.profileID)' loaded profile '\(profile.profileID)'."
                ))
            }
            if let declaredCornerID = entry.cornerID, declaredCornerID != profile.technology.cornerID {
                diagnostics.append(TimingModelProfileCatalogInspection.Diagnostic(
                    severity: "error",
                    code: "profile-corner-mismatch",
                    message: "Catalog entry '\(entry.profileID)' declares corner '\(declaredCornerID)' but loaded profile corner '\(profile.technology.cornerID)'."
                ))
            }
            return TimingModelProfileCatalogInspection.Profile(
                profileID: entry.profileID,
                displayName: entry.displayName,
                sourceKind: sourceKind,
                declaredCornerID: entry.cornerID,
                profileResourceName: entry.profileResourceName,
                profilePath: resolvedPath,
                defaultProfile: entry.defaultProfile,
                status: diagnostics.isEmpty ? .passed : .failed,
                schemaVersion: profile.schemaVersion,
                processName: profile.technology.processName,
                cornerID: profile.technology.cornerID,
                deviceModelID: profile.technology.deviceModelID,
                supplyVoltage: profile.model.supplyVoltage,
                deviceModelHash: modelHash,
                sha256: digest.sha256,
                diagnostics: diagnostics
            )
        } catch {
            return failedTimingModelProfileInspection(
                for: entry,
                sourceKind: sourceKind,
                profilePath: resolvedPath,
                code: "profile-load-failed",
                error: error
            )
        }
    }

    private func failedTimingModelProfileInspection(
        for entry: TimingModelProfileCatalog.Entry,
        sourceKind: TimingModelProfileSelection.SourceKind,
        profilePath: String?,
        code: String,
        error: Error
    ) -> TimingModelProfileCatalogInspection.Profile {
        TimingModelProfileCatalogInspection.Profile(
            profileID: entry.profileID,
            displayName: entry.displayName,
            sourceKind: sourceKind,
            declaredCornerID: entry.cornerID,
            profileResourceName: entry.profileResourceName,
            profilePath: profilePath,
            defaultProfile: entry.defaultProfile,
            status: .failed,
            schemaVersion: nil,
            processName: nil,
            cornerID: nil,
            deviceModelID: nil,
            supplyVoltage: nil,
            deviceModelHash: nil,
            sha256: nil,
            diagnostics: [
                TimingModelProfileCatalogInspection.Diagnostic(
                    severity: "error",
                    code: code,
                    message: String(describing: error)
                ),
            ]
        )
    }

    private func bundledTimingModelProfileURL(resourceName: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw Level1DeviceModelProfileError.missingBundledResource(resourceName)
        }
        return url
    }
}
