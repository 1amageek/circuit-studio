import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("Level-1 device model profile")
struct Level1DeviceModelProfileTests {

    @Test("Bundled level-1 device model profile loads timing model data")
    func bundledLevel1DeviceModelProfileLoadsTimingModelData() throws {
        let profile = try Level1DeviceModelProfile.bundled(
            resourceName: Level1DeviceModel.bundledDefaultProfileResourceName()
        )

        #expect(profile.profileID == "sky130.level1-device-model.v1")
        #expect(profile.technology.processName == "sky130-like-level1")
        #expect(profile.technology.cornerID == "tt")
        #expect(profile.technology.deviceModelID == "level1-sky130-like")
        #expect(profile.model.supplyVoltage == 1.8)
        #expect(profile.model.nmosModelName == "NM")
        #expect(profile.model.pmosModelName == "PM")
        #expect(profile.model.nmosCard.contains("NMOS"))
        #expect(profile.model.pmosCard.contains("PMOS"))
        #expect(profile.model.oxideCapPerArea == 0.0085)
    }

    @Test("Default level-1 model entry point loads the catalog-selected bundled profile")
    func defaultLevel1ModelEntryPointLoadsBundledProfile() throws {
        let profile = try Level1DeviceModelProfile.bundled(
            resourceName: Level1DeviceModel.bundledDefaultProfileResourceName()
        )
        let model = Level1DeviceModel.bundledDefault()

        #expect(model == profile.model)
    }

    @Test("Level-1 device model profile exports timing technology provenance")
    func level1DeviceModelProfileExportsTimingTechnologyProvenance() throws {
        let profile = try Level1DeviceModelProfile.bundled(
            resourceName: Level1DeviceModel.bundledDefaultProfileResourceName()
        )
        let context = try profile.technologyContext(
            resourceName: Level1DeviceModel.bundledDefaultProfileResourceName()
        )

        #expect(context.processName == profile.technology.processName)
        #expect(context.cornerID == profile.technology.cornerID)
        #expect(context.deviceModelID == profile.technology.deviceModelID)
        #expect(context.deviceModelHash == (try TimingTopologyHasher.hashModel(profile.model)))
        #expect(context.modelProfile?.profileID == profile.profileID)
        #expect(context.modelProfile?.resourceName == Level1DeviceModel.bundledDefaultProfileResourceName())
    }

    @Test("Bundled timing model profile catalog selects the default profile")
    func bundledTimingModelProfileCatalogSelectsDefaultProfile() throws {
        let catalog = try TimingModelProfileCatalog.bundled()
        let entry = try catalog.entry(profileID: nil)

        #expect(catalog.catalogID == "circuit-studio.default-timing-model-profiles.v2")
        #expect(catalog.profiles.count == 3)
        #expect(entry.profileID == "sky130.level1-device-model.v1")
        #expect(entry.cornerID == "tt")
        #expect(entry.profileResourceName == Level1DeviceModel.bundledDefaultProfileResourceName())
        #expect(entry.defaultProfile)
    }

    @Test("Bundled timing model profile catalog loads every declared corner resource")
    func bundledTimingModelProfileCatalogLoadsEveryDeclaredCornerResource() throws {
        let catalog = try TimingModelProfileCatalog.bundled()
        let expectedCorners = Set(["tt", "ss", "ff"])

        #expect(Set(catalog.profiles.compactMap(\.cornerID)) == expectedCorners)
        for entry in catalog.profiles {
            let resourceName = try #require(entry.profileResourceName)
            let profile = try Level1DeviceModelProfile.bundled(resourceName: resourceName)

            #expect(profile.profileID == entry.profileID)
            #expect(profile.technology.cornerID == entry.cornerID)
        }
        #expect(try catalog.entry(profileID: nil, cornerID: "tt").profileID == "sky130.level1-device-model.v1")
        #expect(try catalog.entry(profileID: nil, cornerID: "ss").profileID == "sky130.level1-device-model.ss.v1")
        #expect(try catalog.entry(profileID: nil, cornerID: "ff").profileID == "sky130.level1-device-model.ff.v1")
    }

    @Test("Timing model profile catalog selects profiles by declared corner")
    func timingModelProfileCatalogSelectsProfilesByDeclaredCorner() throws {
        let catalog = try TimingModelProfileCatalog(
            catalogID: "unit-catalog",
            profiles: [
                TimingModelProfileCatalog.Entry(
                    profileID: "profile-tt",
                    cornerID: "tt",
                    profilePath: "tt.json",
                    defaultProfile: true
                ),
                TimingModelProfileCatalog.Entry(
                    profileID: "profile-ss",
                    cornerID: "ss",
                    profilePath: "ss.json"
                ),
            ]
        )

        #expect(try catalog.entry(profileID: nil, cornerID: "ss").profileID == "profile-ss")
        #expect(throws: TimingModelProfileCatalogError.cornerNotFound("ff")) {
            _ = try catalog.entry(profileID: nil, cornerID: "ff")
        }
        #expect(throws: TimingModelProfileCatalogError.profileCornerMismatch(
            profileID: "profile-tt",
            expectedCornerID: "ss",
            actualCornerID: "tt"
        )) {
            _ = try catalog.entry(profileID: "profile-tt", cornerID: "ss")
        }
    }

    @Test("Timing model profile catalog rejects duplicate profile IDs")
    func timingModelProfileCatalogRejectsDuplicateProfileIDs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TimingModelProfileCatalogInvalidTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { removeCoreTestTemporaryDirectory(directory) }
        let url = directory.appending(path: "invalid-timing-model-profile-catalog.json")
        let json = """
        {
          "schemaVersion": 1,
          "kind": "timing-model-profile-catalog",
          "catalogID": "invalid-catalog",
          "profiles": [
            {
              "profileID": "profile-1",
              "profileResourceName": "profile-1",
              "defaultProfile": true
            },
            {
              "profileID": "profile-1",
              "profilePath": "profile-1.json"
            }
          ]
        }
        """
        try json.write(to: url, atomically: true, encoding: .utf8)

        #expect(throws: TimingModelProfileCatalogError.duplicateProfileID("profile-1")) {
            _ = try TimingModelProfileCatalog.load(from: url)
        }
    }

    @Test("Custom level-1 model context does not claim bundled profile provenance")
    func customLevel1ModelContextDoesNotClaimBundledProfileProvenance() throws {
        let custom = Level1DeviceModel(
            supplyVoltage: 1.2,
            nmosModelName: "NX",
            pmosModelName: "PX",
            nmosCard: ".model NX NMOS level=1 vto=0.35 kp=100u",
            pmosCard: ".model PX PMOS level=1 vto=-0.35 kp=35u",
            oxideCapPerArea: 0.006
        )
        let context = Level1DeviceModel.technologyContext(for: custom)

        #expect(context.processName == "custom-level1")
        #expect(context.cornerID == "unspecified")
        #expect(context.deviceModelID == "custom-level1-device-model")
        #expect(context.deviceModelHash == (try TimingTopologyHasher.hashModel(custom)))
        #expect(context.modelProfile == nil)
    }

    @Test("Level1DeviceModelProfile rejects incomplete model cards")
    func level1DeviceModelProfileRejectsIncompleteModelCards() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Level1DeviceModelProfileInvalidTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { removeCoreTestTemporaryDirectory(directory) }
        let url = directory.appending(path: "invalid-level1-device-model-profile.json")
        let json = """
        {
          "schemaVersion": 1,
          "profileID": "invalid.level1-device-model.v1",
          "technology": {
            "processName": "invalid",
            "cornerID": "tt",
            "deviceModelID": "invalid-level1"
          },
          "model": {
            "supplyVoltage": 1.8,
            "nmosModelName": "NM",
            "pmosModelName": "PM",
            "nmosCard": "NM NMOS level=1",
            "pmosCard": ".model PM PMOS level=1",
            "oxideCapPerArea": 0.0085
          }
        }
        """
        try json.write(to: url, atomically: true, encoding: .utf8)

        #expect(throws: Level1DeviceModelProfileValidationError.malformedModelCard(
            "model.nmosCard"
        )) {
            _ = try Level1DeviceModelProfile.load(from: url)
        }
    }
}
