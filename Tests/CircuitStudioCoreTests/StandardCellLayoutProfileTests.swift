import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("Standard-cell layout profile")
struct StandardCellLayoutProfileTests {

    @Test("Bundled standard-cell layout profile loads inverter policy from resource")
    func bundledStandardCellLayoutProfileLoadsInverterPolicy() throws {
        let profile = try Self.bundledProfile()

        #expect(profile.profileID == "sky130.standard-cell-layout.v1")
        #expect(profile.targetTechnologyResourceName == Sky130LayoutTech.resourceName)
        #expect(profile.layers.diffusion.name == "diff")
        #expect(profile.layers.contactCut.purpose == "cut")
        #expect(profile.layers.metal2.name == "met2")
        #expect(profile.deviceModels.nmos == "sky130_fd_pr__nfet_01v8")
        #expect(profile.manufacturingGridMicrons == 0.005)
        #expect(profile.inverter.defaultDeviceWidth == 0.42)
        #expect(profile.inverter.minimumDeviceWidth == 0.36)
        #expect(profile.generatedCellLayout.gatePitch == 1.15)
        #expect(profile.circuitRouting.signalTrackSpacingLayer == .metal3)
        #expect(profile.fixedCells["nand2"]?.shapes.count == 24)
        #expect(profile.fixedCells["nor2"]?.devices.count == 4)
    }

    @Test("CMOSGateLibrary derives device sizing from standard-cell profile")
    func cmosGateLibraryDerivesDeviceSizingFromStandardCellProfile() throws {
        let profile = try Self.bundledProfile()
        let library = CMOSGateLibrary(profile: profile)
        let cells = [
            library.inverter(name: "inv_profile"),
            library.nand(name: "nand2_profile", inputs: ["A", "B"]),
            library.nor(name: "nor2_profile", inputs: ["A", "B"]),
        ]

        for cell in cells {
            #expect(cell.devices.allSatisfy { $0.width == profile.generatedCellLayout.deviceWidth })
            #expect(cell.devices.allSatisfy { $0.length == profile.generatedCellLayout.gateLength })
        }
    }

    @Test("BooleanGateMapper uses injected CMOS gate library sizing")
    func booleanGateMapperUsesInjectedCMOSGateLibrarySizing() {
        let library = CMOSGateLibrary(deviceSizing: .init(width: 0.73, length: 0.19))
        let mapper = BooleanGateMapper(cellLibrary: library)
        let netlist = mapper.map(.and(.input("a"), .input("b")), name: "and_profiled")
        let devices = netlist.instances.flatMap(\.cell.devices)

        #expect(!devices.isEmpty)
        #expect(devices.allSatisfy { $0.width == 0.73 })
        #expect(devices.allSatisfy { $0.length == 0.19 })
    }

    @Test("StandardCellLayoutProfile rejects incomplete layer references")
    func standardCellLayoutProfileRejectsIncompleteLayerReferences() throws {
        let profile = try Self.customProfile(
            layers: .init(
                diffusion: .init(name: "active_custom", purpose: ""),
                nImplant: .init(name: "nimplant_custom", purpose: "drawing"),
                pImplant: .init(name: "pimplant_custom", purpose: "drawing"),
                nWell: .init(name: "well_custom", purpose: "drawing"),
                gateConductor: .init(name: "gate_custom", purpose: "drawing"),
                localInterconnect: .init(name: "local_custom", purpose: "drawing"),
                contactCut: .init(name: "contact_custom", purpose: "cut"),
                localInterconnectToMetalContact: .init(name: "local_to_metal_custom", purpose: "cut"),
                metal1: .init(name: "metal1_custom", purpose: "drawing"),
                metal1ToMetal2Via: .init(name: "metal1_to_metal2_custom", purpose: "cut"),
                metal2: .init(name: "metal2_custom", purpose: "drawing"),
                gateContactImplant: .init(name: "gate_contact_implant_custom", purpose: "drawing"),
                metal3: .init(name: "metal3_custom", purpose: "drawing")
            )
        )
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "StandardCellLayoutProfileInvalidTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { removeCoreTestTemporaryDirectory(directory) }
        let url = directory.appending(path: "invalid-standard-cell-layout-profile.json")
        try JSONEncoder().encode(profile).write(to: url)

        #expect(throws: StandardCellLayoutProfileValidationError.emptyField(
            "layers.diffusion.purpose"
        )) {
            _ = try StandardCellLayoutProfile.load(from: url)
        }
    }

    @Test("ProfiledInverterGenerator uses injected profile layers and device models")
    func inverterGeneratorUsesInjectedProfileLayersAndDeviceModels() throws {
        let profile = try Self.customProfile(
            layers: .init(
                diffusion: .init(name: "active_custom", purpose: "drawing"),
                nImplant: .init(name: "nimplant_custom", purpose: "drawing"),
                pImplant: .init(name: "pimplant_custom", purpose: "drawing"),
                nWell: .init(name: "well_custom", purpose: "drawing"),
                gateConductor: .init(name: "gate_custom", purpose: "drawing"),
                localInterconnect: .init(name: "local_custom", purpose: "drawing"),
                contactCut: .init(name: "contact_custom", purpose: "cut"),
                localInterconnectToMetalContact: .init(name: "local_to_metal_custom", purpose: "cut"),
                metal1: .init(name: "metal1_custom", purpose: "drawing"),
                metal1ToMetal2Via: .init(name: "metal1_to_metal2_custom", purpose: "cut"),
                metal2: .init(name: "metal2_custom", purpose: "drawing"),
                gateContactImplant: .init(name: "gate_contact_implant_custom", purpose: "drawing"),
                metal3: .init(name: "metal3_custom", purpose: "drawing")
            ),
            deviceModels: .init(nmos: "custom_nfet", pmos: "custom_pfet")
        )
        let generator = ProfiledInverterGenerator(profile: profile)
        let document = generator.generate(name: "INV_CUSTOM")
        let layerNames = Set(document.cells.flatMap { $0.shapes.map(\.layer.name) })
        let labelLayerNames = Set(document.cells.flatMap { $0.labels.map(\.layer.name) })
        let schematic = generator.schematic(name: "INV_CUSTOM")

        #expect(layerNames.contains("active_custom"))
        #expect(layerNames.contains("contact_custom"))
        #expect(!layerNames.contains("diff"))
        #expect(labelLayerNames.contains("local_custom"))
        #expect(schematic.contains("custom_pfet"))
        #expect(schematic.contains("custom_nfet"))
    }

    @Test("ProfiledStandardCellGenerator rejects missing fixed cells")
    func profiledStandardCellGeneratorRejectsMissingFixedCells() throws {
        let profile = try Self.bundledProfile()
        let generator = ProfiledStandardCellGenerator(cellID: "missing_cell", profile: profile)

        #expect(throws: ProfiledStandardCellGenerator.GeneratorError.missingFixedCell("missing_cell")) {
            _ = try generator.generateChecked()
        }
    }

    @Test("StandardCellLayoutProfile rejects zero-height fixed-cell shapes")
    func standardCellLayoutProfileRejectsZeroHeightFixedCellShapes() throws {
        let base = try Self.bundledProfile()
        let nand = try #require(base.fixedCells["nand2"])
        let invalidShape = StandardCellLayoutProfile.FixedCellShape(
            layer: nand.shapes[0].layer,
            rect: .init(x: 0, y: 0, width: 1, height: 0)
        )
        var shapes = nand.shapes
        shapes[0] = invalidShape
        let invalidNand = StandardCellLayoutProfile.FixedCellLayout(
            defaultName: nand.defaultName,
            ports: nand.ports,
            comment: nand.comment,
            shapes: shapes,
            labels: nand.labels,
            devices: nand.devices
        )
        var fixedCells = base.fixedCells
        fixedCells["nand2"] = invalidNand
        let profile = try Self.customProfile(
            layers: base.layers,
            deviceModels: base.deviceModels,
            fixedCells: fixedCells
        )
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "StandardCellLayoutProfileInvalidFixedCellTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { removeCoreTestTemporaryDirectory(directory) }
        let url = directory.appending(path: "invalid-fixed-cell-profile.json")
        try JSONEncoder().encode(profile).write(to: url)

        #expect(throws: StandardCellLayoutProfileValidationError.nonPositiveValue(
            "fixedCells.nand2.shapes[0].rect.height"
        )) {
            _ = try StandardCellLayoutProfile.load(from: url)
        }
    }

    @Test("NAND2 and NOR2 compatibility generators use injected fixed-cell catalog profile")
    func nandNorCompatibilityGeneratorsUseInjectedCatalogProfile() throws {
        let base = try Self.bundledProfile()
        let profile = try Self.customProfile(
            layers: .init(
                diffusion: .init(name: "active_custom", purpose: "drawing"),
                nImplant: .init(name: "nimplant_custom", purpose: "drawing"),
                pImplant: .init(name: "pimplant_custom", purpose: "drawing"),
                nWell: .init(name: "well_custom", purpose: "drawing"),
                gateConductor: .init(name: "gate_custom", purpose: "drawing"),
                localInterconnect: .init(name: "local_custom", purpose: "drawing"),
                contactCut: .init(name: "contact_custom", purpose: "cut"),
                localInterconnectToMetalContact: .init(name: "local_to_metal_custom", purpose: "cut"),
                metal1: .init(name: "metal1_custom", purpose: "drawing"),
                metal1ToMetal2Via: .init(name: "metal1_to_metal2_custom", purpose: "cut"),
                metal2: .init(name: "metal2_custom", purpose: "drawing"),
                gateContactImplant: .init(name: "gate_contact_implant_custom", purpose: "drawing"),
                metal3: .init(name: "metal3_custom", purpose: "drawing")
            ),
            deviceModels: .init(nmos: "custom_nfet", pmos: "custom_pfet"),
            fixedCells: base.fixedCells
        )

        let nandGenerator = ProfiledStandardCellGenerator(cellID: "nand2", profile: profile)
        let norGenerator = ProfiledStandardCellGenerator(cellID: "nor2", profile: profile)
        let nandDocument = nandGenerator.generate(name: "NAND_CUSTOM")
        let norDocument = norGenerator.generate(name: "NOR_CUSTOM")
        let nandLayers = Set(nandDocument.cells.flatMap { $0.shapes.map(\.layer.name) })
        let norLayers = Set(norDocument.cells.flatMap { $0.shapes.map(\.layer.name) })
        let nandSchematic = nandGenerator.schematic(name: "NAND_CUSTOM")
        let norSchematic = norGenerator.schematic(name: "NOR_CUSTOM")

        #expect(nandLayers.contains("active_custom"))
        #expect(nandLayers.contains("contact_custom"))
        #expect(!nandLayers.contains("diff"))
        #expect(norLayers.contains("local_custom"))
        #expect(norLayers.contains("well_custom"))
        #expect(nandSchematic.contains("custom_pfet"))
        #expect(nandSchematic.contains("custom_nfet"))
        #expect(norSchematic.contains("custom_pfet"))
        #expect(norSchematic.contains("custom_nfet"))
    }

    @Test("StandardCellSynthesizer uses injected dynamic layout profile")
    func standardCellSynthesizerUsesInjectedDynamicLayoutProfile() throws {
        let profile = try Self.customProfile(
            layers: .init(
                diffusion: .init(name: "active_custom", purpose: "drawing"),
                nImplant: .init(name: "nimplant_custom", purpose: "drawing"),
                pImplant: .init(name: "pimplant_custom", purpose: "drawing"),
                nWell: .init(name: "well_custom", purpose: "drawing"),
                gateConductor: .init(name: "gate_custom", purpose: "drawing"),
                localInterconnect: .init(name: "local_custom", purpose: "drawing"),
                contactCut: .init(name: "contact_custom", purpose: "cut"),
                localInterconnectToMetalContact: .init(name: "local_to_metal_custom", purpose: "cut"),
                metal1: .init(name: "metal1_custom", purpose: "drawing"),
                metal1ToMetal2Via: .init(name: "metal1_to_metal2_custom", purpose: "cut"),
                metal2: .init(name: "metal2_custom", purpose: "drawing"),
                gateContactImplant: .init(name: "gate_contact_implant_custom", purpose: "drawing"),
                metal3: .init(name: "metal3_custom", purpose: "drawing")
            ),
            deviceModels: .init(nmos: "custom_nfet", pmos: "custom_pfet")
        )
        let synth = StandardCellSynthesizer(profile: profile)
        let layout = try synth.layout(.inverter(name: "INV_DYNAMIC", input: "A", output: "Y"))
        let layerNames = Set(layout.shapes.map(\.layer.name))
        let schematic = synth.schematic(.inverter(name: "INV_DYNAMIC", input: "A", output: "Y"))

        #expect(layout.fieldY == profile.generatedCellLayout.fieldY)
        #expect(layout.outputBusY == profile.generatedCellLayout.outputBusY)
        #expect(layerNames.contains("active_custom"))
        #expect(layerNames.contains("metal2_custom"))
        #expect(!layerNames.contains("diff"))
        #expect(schematic.contains("custom_pfet"))
        #expect(schematic.contains("custom_nfet"))
    }

    @Test("StandardCircuitSynthesizer uses injected routing profile and device models")
    func circuitSynthesizerUsesInjectedRoutingProfileAndDeviceModels() throws {
        let base = try Self.bundledProfile()
        let routing = StandardCellLayoutProfile.CircuitRouting(
            cellGap: base.circuitRouting.cellGap,
            firstSignalTrackY: 4.25,
            signalTrackAccessPadWidth: base.circuitRouting.signalTrackAccessPadWidth,
            signalTrackRuleMargin: base.circuitRouting.signalTrackRuleMargin,
            antennaTieBaseY: base.circuitRouting.antennaTieBaseY,
            signalTrackSpacingLayer: base.circuitRouting.signalTrackSpacingLayer,
            constantGroundStrapTopY: base.circuitRouting.constantGroundStrapTopY,
            constantPowerStrapTopY: base.circuitRouting.constantPowerStrapTopY,
            barycenterIterations: base.circuitRouting.barycenterIterations
        )
        let profile = try Self.customProfile(
            layers: base.layers,
            deviceModels: .init(nmos: "custom_nfet", pmos: "custom_pfet"),
            circuitRouting: routing
        )
        let technology = try LayoutTechnologyResource.bundled(
            resourceName: base.targetTechnologyResourceName
        )
        let synth = StandardCircuitSynthesizer(
            profile: profile,
            layoutTechnology: technology
        )
        let netlist = GateLevelNetlist.inverterChain(name: "chain_profiled", stages: 2)
        let candidates = try synth.antennaProtectionCandidates(for: netlist)
        let schematic = synth.referenceSPICE(for: netlist)

        #expect(candidates.map(\.trackYMicrons).min() == 4.25)
        #expect(schematic.contains("custom_pfet"))
        #expect(schematic.contains("custom_nfet"))
    }

    private static func customProfile(
        layers: StandardCellLayoutProfile.Layers,
        deviceModels: StandardCellLayoutProfile.DeviceModels = .init(
            nmos: "custom_nfet",
            pmos: "custom_pfet"
        ),
        generatedCellLayout: StandardCellLayoutProfile.GeneratedCellLayout? = nil,
        circuitRouting: StandardCellLayoutProfile.CircuitRouting? = nil,
        fixedCells: [String: StandardCellLayoutProfile.FixedCellLayout] = [:]
    ) throws -> StandardCellLayoutProfile {
        let base = try Self.bundledProfile()
        return StandardCellLayoutProfile(
            schemaVersion: 1,
            profileID: "custom.standard-cell-layout.v1",
            targetTechnologyResourceName: "custom-layout-tech",
            manufacturingGridMicrons: base.manufacturingGridMicrons,
            layers: layers,
            deviceModels: deviceModels,
            inverter: base.inverter,
            generatedCellLayout: generatedCellLayout ?? base.generatedCellLayout,
            circuitRouting: circuitRouting ?? base.circuitRouting,
            fixedCells: fixedCells
        )
    }

    private static func bundledProfile() throws -> StandardCellLayoutProfile {
        try StandardCellLayoutProfileCatalog.loadDefaultProfile()
    }
}
