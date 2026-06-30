import Foundation
import DesignFlowKernel
import Testing
import LayoutCore
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

@Suite("DesignFlowService timing profile commands", .serialized)
struct DesignFlowTimingProfileCommandTests {
    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIBuildsTimingLibraryWithCatalogSelectedExternalModelProfile() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("timing-model-profile-library")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let profileURL = root.appending(path: "external-timing-profile.json")
        let profile = Level1DeviceModel.bundledDefaultProfile()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: profileURL, options: .atomic)
        let profileDigest = try RoundTripArtifactDigest.compute(url: profileURL)
        let catalogURL = root.appending(path: "timing-profile-catalog.json")
        let catalog = try TimingModelProfileCatalog(
            catalogID: "unit-timing-profile-catalog",
            profiles: [
                TimingModelProfileCatalog.Entry(
                    profileID: profile.profileID,
                    cornerID: profile.technology.cornerID,
                    profilePath: profileURL.lastPathComponent,
                    defaultProfile: true
                ),
            ]
        )
        try encoder.encode(catalog).write(to: catalogURL, options: .atomic)
        try await DesignFlowServiceTestSupport.prewarmTimingLibraryBuildCache(
            model: profile.model,
            technologyContext: try profile.technologyContext(
                path: profileURL.path(percentEncoded: false),
                sha256: profileDigest.sha256
            )
        )

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .buildTimingLibrary,
            projectRootPath: root.path(percentEncoded: false),
            runID: "timing-profile-run",
            timingModelProfileCatalogPath: catalogURL.path(percentEncoded: false),
            timingModelCornerID: profile.technology.cornerID
        ))

        #expect(result.runID == "timing-profile-run")
        #expect(result.projectRootPath == root.path(percentEncoded: false))
        #expect(result.timingModelProfileID == profile.profileID)
        #expect(result.timingModelProfilePath == profileURL.path(percentEncoded: false))
        #expect(result.timingModelProfileCatalogID == catalog.catalogID)
        #expect(result.timingModelProfileCatalogPath == catalogURL.path(percentEncoded: false))
        #expect(result.timingModelCornerID == profile.technology.cornerID)
        let manifestPath = try #require(result.timingArtifactManifestPath)
        let libraryPath = try #require(result.timingLibraryPath)
        let selectionPath = try #require(result.timingModelProfileSelectionPath)
        #expect(FileManager.default.fileExists(atPath: manifestPath))
        #expect(FileManager.default.fileExists(atPath: libraryPath))
        #expect(FileManager.default.fileExists(atPath: selectionPath))

        let manifest = try JSONDecoder().decode(
            TimingArtifactManifest.self,
            from: Data(contentsOf: URL(filePath: manifestPath))
        )
        #expect(manifest.runID == "timing-profile-run")
        #expect(manifest.technology.modelProfile?.profileID == profile.profileID)
        #expect(manifest.technology.modelProfile?.path == profileURL.path(percentEncoded: false))
        #expect(manifest.technology.modelProfile?.sha256 == profileDigest.sha256)
        #expect(manifest.artifacts.contains { $0.id == "timing-library" && $0.status == .available })
        #expect(manifest.artifacts.contains { $0.id == "timing-model-profile-selection" && $0.status == .available })
        #expect(manifest.artifacts.contains { $0.id == "combinational-characterization" && $0.status == .available })
        #expect(manifest.artifacts.contains { $0.id == "sequential-dff-characterization" && $0.status == .available })

        let selection = try JSONDecoder().decode(
            TimingModelProfileSelection.self,
            from: Data(contentsOf: URL(filePath: selectionPath))
        )
        #expect(selection.runID == "timing-profile-run")
        #expect(selection.sourceKind == .externalFile)
        #expect(selection.catalogID == catalog.catalogID)
        #expect(selection.catalogPath == catalogURL.path(percentEncoded: false))
        #expect(selection.profile.profileID == profile.profileID)
        #expect(selection.profile.path == profileURL.path(percentEncoded: false))
        #expect(selection.profile.sha256 == profileDigest.sha256)
        #expect(selection.technology.modelProfile == selection.profile)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRejectsCatalogTimingModelProfileCornerMismatchBeforeBuild() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("timing-model-profile-corner-mismatch")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let profileURL = root.appending(path: "external-timing-profile.json")
        let profile = Level1DeviceModel.bundledDefaultProfile()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: profileURL, options: .atomic)
        let catalogURL = root.appending(path: "timing-profile-catalog.json")
        let catalog = try TimingModelProfileCatalog(
            catalogID: "unit-timing-profile-catalog",
            profiles: [
                TimingModelProfileCatalog.Entry(
                    profileID: profile.profileID,
                    cornerID: "ss",
                    profilePath: profileURL.lastPathComponent,
                    defaultProfile: true
                ),
            ]
        )
        try encoder.encode(catalog).write(to: catalogURL, options: .atomic)

        await #expect(throws: DesignFlowCommandError.timingModelProfileCatalogCornerMismatch(
            profileID: profile.profileID,
            declared: "ss",
            actual: profile.technology.cornerID
        )) {
            try await DesignFlowService().execute(DesignFlowCommand(
                kind: .buildTimingLibrary,
                projectRootPath: root.path(percentEncoded: false),
                runID: "timing-profile-corner-mismatch",
                timingModelProfileCatalogPath: catalogURL.path(percentEncoded: false)
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRejectsConflictingTimingModelProfileSelectors() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("timing-model-profile-conflict")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }

        await #expect(throws: DesignFlowCommandError.conflictingTimingModelProfileSelectors) {
            try await DesignFlowService().execute(DesignFlowCommand(
                kind: .buildTimingLibrary,
                projectRootPath: root.path(percentEncoded: false),
                runID: "timing-profile-conflict",
                timingModelProfilePath: "/tmp/timing-profile.json",
                timingModelProfileCatalogPath: "/tmp/timing-profile-catalog.json",
                timingModelProfileID: "profile-1",
                timingModelCornerID: "tt"
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIInspectsBundledTimingModelProfileCatalog() async throws {
        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .inspectTimingModelProfiles
        ))

        let inspection = try #require(result.timingModelProfileCatalogInspection)
        #expect(result.timingModelProfileCatalogID == "circuit-studio.default-timing-model-profiles.v2")
        #expect(result.timingModelProfileID == "sky130.level1-device-model.v1")
        #expect(result.timingModelCornerID == "tt")
        #expect(inspection.status == .passed)
        #expect(inspection.profileCount == 3)
        #expect(inspection.passedProfileCount == 3)
        #expect(inspection.failedProfileCount == 0)
        let profile = try #require(inspection.profiles.first)
        #expect(profile.profileID == "sky130.level1-device-model.v1")
        #expect(profile.profileResourceName == Level1DeviceModel.bundledDefaultProfileResourceName())
        #expect(profile.profilePath == nil)
        #expect(profile.declaredCornerID == "tt")
        #expect(profile.cornerID == "tt")
        #expect(profile.deviceModelHash != nil)
        #expect(profile.sha256 != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIInspectsBundledTimingModelProfileCatalogByCorner() async throws {
        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .inspectTimingModelProfiles,
            timingModelCornerID: "ss"
        ))

        let inspection = try #require(result.timingModelProfileCatalogInspection)
        #expect(result.timingModelProfileCatalogID == "circuit-studio.default-timing-model-profiles.v2")
        #expect(result.timingModelProfileID == "sky130.level1-device-model.ss.v1")
        #expect(result.timingModelCornerID == "ss")
        #expect(inspection.status == .passed)
        #expect(inspection.profileCount == 3)
        #expect(inspection.passedProfileCount == 3)
        let selectedProfile = try #require(inspection.profiles.first { $0.profileID == result.timingModelProfileID })
        #expect(selectedProfile.declaredCornerID == "ss")
        #expect(selectedProfile.cornerID == "ss")
        #expect(selectedProfile.profileResourceName == "sky130-level1-device-model-profile-ss")
        #expect(selectedProfile.deviceModelHash != nil)
        #expect(selectedProfile.sha256 != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIInspectsTimingModelProfileCatalogEntryFailures() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("timing-model-profile-inspect-failure")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let catalogURL = root.appending(path: "timing-profile-catalog.json")
        let catalog = try TimingModelProfileCatalog(
            catalogID: "broken-timing-profile-catalog",
            profiles: [
                TimingModelProfileCatalog.Entry(
                    profileID: "missing-profile",
                    cornerID: "tt",
                    profilePath: "missing-profile.json",
                    defaultProfile: true
                ),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(catalog).write(to: catalogURL, options: .atomic)

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .inspectTimingModelProfiles,
            timingModelProfileCatalogPath: catalogURL.path(percentEncoded: false)
        ))

        let inspection = try #require(result.timingModelProfileCatalogInspection)
        #expect(inspection.status == .failed)
        #expect(inspection.profileCount == 1)
        #expect(inspection.failedProfileCount == 1)
        let profile = try #require(inspection.profiles.first)
        #expect(profile.status == .failed)
        #expect(profile.declaredCornerID == "tt")
        #expect(profile.profilePath == root.appending(path: "missing-profile.json").path(percentEncoded: false))
        #expect(profile.diagnostics.first?.code == "profile-load-failed")
    }
}
