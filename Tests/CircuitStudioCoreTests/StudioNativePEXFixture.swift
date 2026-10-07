import Foundation
import Testing
import CircuiteFoundation
import LayoutCore
import LayoutTech
import LayoutIO
import LayoutVerify
import PEXEngine
import PEXNative
@testable import CircuitStudioApp

/// Nonproduction analytical sheet inputs for the Studio ingestion boundary.
struct StudioNativePEXFixture {
    let root: URL
    let configuration: NativePEXConfiguration
    let reference: PEXNativeInputReference
    let calibrationID: ArtifactID
    let originalInputs: [URL: Data]
    let referencePath = ".xcircuite/native reference \"sheet\".json"

    init(root: URL, maximumMeshCells: Int = 100) throws {
        self.root = root
        let tech = LayoutTechDatabase.standard()
        let layer = LayoutLayerID(name: "M1", purpose: "drawing")
        let netID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
        let cell = LayoutCell(name: "TOP", shapes: [
            .init(layer: layer, geometry: .rect(.init(origin: .zero, size: .init(width: 1, height: 1))))
        ])
        let source = LayoutDocument(name: "Studio analytical sheet", cells: [cell], topCellID: cell.id)
        let layoutURL = root.appending(path: "sheet.gds")
        let converter = MaskDataFormatConverter(tech: tech)
        try converter.exportDocument(source, to: layoutURL, format: .gds)
        var imported = try converter.importDocument(from: layoutURL, format: .gds)
        let topIndex = try #require(imported.cells.firstIndex { $0.name == "TOP" })
        let pins = ["A", "B"].map { name in
            NativePEXPinDefinition(cellName: "TOP", pin: .init(name: name,
                position: .init(x: 0.5, y: 0.5), size: .init(width: 1, height: 1), layer: layer, netID: netID))
        }
        #expect(imported.cells[topIndex].pins.isEmpty)
        imported.cells[topIndex].pins.append(contentsOf: pins.map(\.pin))
        let captured = try LayoutConnectivityExtractor().captureConductors(document: imported,
            tech: tech, conductiveLayers: [layer], cellID: imported.cells[topIndex].id)
        #expect(captured.hierarchy.units == imported.units)
        let units = captured.coordinateUnits
        let fullWidth = try #require(Int32(exactly: units.scale.databaseUnits(forMicrometers: 1)))
        #expect(units.scale.micrometers(forDatabaseUnits: Int64(fullWidth)) == 1)
        configuration = try NativePEXConfiguration(layoutTechnology: tech,
            layers: [.init(layerID: layer, electricalName: "M1", isConductive: true)],
            supplementalPins: pins,
            netBindings: [.init(occurrenceIndex: 0, netID: netID, netName: NetName("SIGNAL"))],
            electrodeBindings: [
                .init(pinIndex: 0, terminal: .init(netName: NetName("SIGNAL"), nodeName: NodeName("A")),
                    faces: [.init(side: .minX, coordinate: 0, begin: 0, end: fullWidth)]),
                .init(pinIndex: 1, terminal: .init(netName: NetName("SIGNAL"), nodeName: NodeName("B")),
                    faces: [.init(side: .maxX, coordinate: fullWidth, begin: 0, end: fullWidth)])
            ], expectedCoordinateUnits: units, maximumCellSpanDatabaseUnits: fullWidth,
            calculationLimits: .init(maximumMeshCells: maximumMeshCells))

        // These bytes define an analytical test law, not measured/fitted process data.
        let calibrationBytes = Data("""
        Studio analytical sheet law v1, nonproduction
        analyticalRectilinearV1; M1 bottom=0m thickness=1e-6m resistivity=2e-8ohm*m
        groundArea=1e-4F/m^2 groundPerimeter=1e-10F/m
        M1/M1 couplingArea=1e-5F/m^2 couplingSidewall=1e-16F
        width,length,gap range=[1e-12,1]m; temperature=298.15K voltage=1.8V reference=0
        """.utf8)
        calibrationID = try ArtifactID(digest: .init(algorithm: .sha256,
            hexadecimalValue: PEXArtifactResolver.sha256(data: calibrationBytes)),
            byteCount: UInt64(calibrationBytes.count))
        let calibrationURL = root.appending(path: "sample-law.txt")
        try calibrationBytes.write(to: calibrationURL)
        let range = PEXDimensionRangeMeters(minimumMeters: 1e-12, maximumMeters: 1)
        let model = PEXElectricalModel(law: .analyticalRectilinearV1, coplanarScreening: nil,
            processName: "studio-analytical-sheet", cornerID: "tt", temperatureKelvin: 298.15,
            voltageVolts: 1.8, parameters: [:], referenceNodeName: "0", calibrationArtifacts: [calibrationID],
            conductors: [.init(layerName: "M1", bottomHeightMeters: 0, thicknessMeters: 1e-6,
                resistivityOhmMeters: 2e-8, groundAreaFaradsPerSquareMeter: 1e-4,
                groundPerimeterFaradsPerMeter: 1e-10, widthRange: range, lengthRange: range)],
            vias: [], couplings: [.init(firstLayerName: "M1", secondLayerName: "M1",
                areaFaradsPerSquareMeter: 1e-5, sidewallFarads: 1e-16, gapRange: range)])
        let technology = TechnologyIR(processName: "studio-analytical-sheet",
            stack: [.init(name: "M1", order: 0)], logicalToPhysicalLayerMap: [:], vias: [],
            defaultExtractionRules: .default, backendHints: [:], electricalModels: [model])
        let configurationURL = root.appending(path: "native-configuration.json")
        try JSONEncoder().encode(configuration).write(to: configurationURL)
        reference = try PEXNativeInputReference(configurationURL: configurationURL,
            calibrations: [.init(artifactID: calibrationID, url: calibrationURL)])
        try JSONEncoder().encode(reference).write(to: root.appending(path: referencePath))
        let technologyURL = root.appending(path: "technology.json")
        try JSONEncoder().encode(technology).write(to: technologyURL)
        let netlistURL = root.appending(path: "source.spice")
        try Data(".subckt TOP A B\n.ends TOP\n".utf8).write(to: netlistURL)
        originalInputs = try Dictionary(uniqueKeysWithValues:
            [layoutURL, configurationURL, calibrationURL, technologyURL, netlistURL,
             root.appending(path: referencePath)].map { ($0, try Data(contentsOf: $0)) })
    }

    func projectConfig(workspace: String) -> PEXProjectConfig {
        PEXProjectConfig(enabled: true, topCell: "TOP", backendID: "native", corners: ["tt"],
            inputs: .init(layout: "sheet.gds", netlist: "source.spice",
                technology: "technology.json", nativeInput: referencePath),
            output: .init(workspace: workspace), options: .init(strictValidation: true))
    }

    func assertOriginalInputsUnchanged() throws {
        for (url, bytes) in originalInputs { #expect(try Data(contentsOf: url) == bytes) }
    }
}
