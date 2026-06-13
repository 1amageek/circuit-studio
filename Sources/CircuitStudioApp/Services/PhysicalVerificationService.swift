import Foundation
import CircuitStudioCore
import LayoutCore
import LayoutTech
import LayoutVerify

public struct PhysicalVerificationReport: Sendable, Hashable {
    public let drc: DRCVerificationReport
    public let lvs: LVSVerificationReport
    public let externalSignoff: ExternalSignoffReview?

    public init(
        drc: DRCVerificationReport,
        lvs: LVSVerificationReport,
        externalSignoff: ExternalSignoffReview? = nil
    ) {
        self.drc = drc
        self.lvs = lvs
        self.externalSignoff = externalSignoff
    }

    public var isReadyForPEX: Bool {
        drc.passed && lvs.passed && (externalSignoff?.isReadyForPEX ?? true)
    }
}

public struct DRCVerificationReport: Sendable, Hashable {
    public let violationCount: Int
    public let violationsByKind: [String: Int]
    public let passed: Bool

    public init(violationCount: Int, violationsByKind: [String: Int], passed: Bool) {
        self.violationCount = violationCount
        self.violationsByKind = violationsByKind
        self.passed = passed
    }
}

public struct LVSVerificationReport: Sendable, Hashable {
    public struct Terminal: Sendable, Hashable {
        public let componentName: String
        public let pinName: String

        public init(componentName: String, pinName: String) {
            self.componentName = componentName
            self.pinName = pinName
        }
    }

    public struct PhysicalShort: Sendable, Hashable {
        public let netNames: [String]
        public let terminals: [Terminal]

        public init(netNames: [String], terminals: [Terminal]) {
            self.netNames = netNames
            self.terminals = terminals
        }
    }

    public struct PhysicalOpen: Sendable, Hashable {
        public let netName: String
        public let terminals: [Terminal]
        public let physicalNetCount: Int

        public init(netName: String, terminals: [Terminal], physicalNetCount: Int) {
            self.netName = netName
            self.terminals = terminals
            self.physicalNetCount = physicalNetCount
        }
    }

    public struct TerminalMismatch: Sendable, Hashable {
        public let terminal: Terminal
        public let expectedNetName: String
        public let actualNetNames: [String]

        public init(terminal: Terminal, expectedNetName: String, actualNetNames: [String]) {
            self.terminal = terminal
            self.expectedNetName = expectedNetName
            self.actualNetNames = actualNetNames
        }
    }

    public struct DeviceParameterMismatch: Sendable, Hashable {
        public let componentName: String
        public let parameterName: String
        public let expectedValue: Double
        public let actualValue: Double
        public let tolerance: Double

        public init(
            componentName: String,
            parameterName: String,
            expectedValue: Double,
            actualValue: Double,
            tolerance: Double
        ) {
            self.componentName = componentName
            self.parameterName = parameterName
            self.expectedValue = expectedValue
            self.actualValue = actualValue
            self.tolerance = tolerance
        }
    }

    public let schematicHashMatches: Bool
    public let missingLayoutInstances: [String]
    public let extraLayoutInstances: [String]
    public let missingLayoutNets: [String]
    public let extraLayoutNets: [String]
    public let danglingMappedInstanceIDs: [UUID]
    public let danglingMappedNetIDs: [UUID]
    public let physicalShorts: [PhysicalShort]
    public let physicalOpens: [PhysicalOpen]
    public let unconnectedLayoutPins: [Terminal]
    public let terminalMismatches: [TerminalMismatch]
    public let missingExternalLayoutPorts: [String]
    public let invalidLayoutTerminals: [Terminal]
    public let duplicateLayoutTerminals: [Terminal]
    public let deviceParameterMismatches: [DeviceParameterMismatch]
    public let duplicateLayoutDevices: [String]
    public let layoutTopologyErrors: [String]
    public let connectivityExtractionSkipped: Bool
    public let skippedComponents: [String]

    public init(
        schematicHashMatches: Bool,
        missingLayoutInstances: [String],
        extraLayoutInstances: [String] = [],
        missingLayoutNets: [String],
        extraLayoutNets: [String],
        danglingMappedInstanceIDs: [UUID] = [],
        danglingMappedNetIDs: [UUID] = [],
        physicalShorts: [PhysicalShort] = [],
        physicalOpens: [PhysicalOpen] = [],
        unconnectedLayoutPins: [Terminal] = [],
        terminalMismatches: [TerminalMismatch] = [],
        missingExternalLayoutPorts: [String] = [],
        invalidLayoutTerminals: [Terminal] = [],
        duplicateLayoutTerminals: [Terminal] = [],
        deviceParameterMismatches: [DeviceParameterMismatch] = [],
        duplicateLayoutDevices: [String] = [],
        layoutTopologyErrors: [String] = [],
        connectivityExtractionSkipped: Bool = false,
        skippedComponents: [String]
    ) {
        self.schematicHashMatches = schematicHashMatches
        self.missingLayoutInstances = missingLayoutInstances
        self.extraLayoutInstances = extraLayoutInstances
        self.missingLayoutNets = missingLayoutNets
        self.extraLayoutNets = extraLayoutNets
        self.danglingMappedInstanceIDs = danglingMappedInstanceIDs
        self.danglingMappedNetIDs = danglingMappedNetIDs
        self.physicalShorts = physicalShorts
        self.physicalOpens = physicalOpens
        self.unconnectedLayoutPins = unconnectedLayoutPins
        self.terminalMismatches = terminalMismatches
        self.missingExternalLayoutPorts = missingExternalLayoutPorts
        self.invalidLayoutTerminals = invalidLayoutTerminals
        self.duplicateLayoutTerminals = duplicateLayoutTerminals
        self.deviceParameterMismatches = deviceParameterMismatches
        self.duplicateLayoutDevices = duplicateLayoutDevices
        self.layoutTopologyErrors = layoutTopologyErrors
        self.connectivityExtractionSkipped = connectivityExtractionSkipped
        self.skippedComponents = skippedComponents
    }

    public var passed: Bool {
        schematicHashMatches
            && missingLayoutInstances.isEmpty
            && extraLayoutInstances.isEmpty
            && missingLayoutNets.isEmpty
            && extraLayoutNets.isEmpty
            && danglingMappedInstanceIDs.isEmpty
            && danglingMappedNetIDs.isEmpty
            && physicalShorts.isEmpty
            && physicalOpens.isEmpty
            && unconnectedLayoutPins.isEmpty
            && terminalMismatches.isEmpty
            && missingExternalLayoutPorts.isEmpty
            && invalidLayoutTerminals.isEmpty
            && duplicateLayoutTerminals.isEmpty
            && deviceParameterMismatches.isEmpty
            && duplicateLayoutDevices.isEmpty
            && layoutTopologyErrors.isEmpty
            && !connectivityExtractionSkipped
    }
}

public struct PhysicalVerificationService: Sendable {
    public init() {}

    public func runDRC(document: LayoutDocument, tech: LayoutTechDatabase) -> DRCVerificationReport {
        let result = LayoutDRCService().run(document: document, tech: tech)
        return makeDRCReport(violations: Self.physicalRuleViolations(in: result))
    }

    /// DRC violations that gate physical signoff. Annotation-based
    /// connectivity opens are excluded: net connectivity is judged by
    /// extraction-based LVS, which sees connections through unannotated
    /// cell-member geometry (device terminal pads) that the annotation-scope
    /// open check cannot.
    public static func physicalRuleViolations(in result: LayoutDRCResult) -> [LayoutViolation] {
        result.violations.filter { $0.kind != .disconnectedOpen }
    }

    public func makeDRCReport(violations: [LayoutViolation]) -> DRCVerificationReport {
        var counts: [String: Int] = [:]
        for violation in violations {
            counts[violation.kind.rawValue, default: 0] += 1
        }
        return DRCVerificationReport(
            violationCount: violations.count,
            violationsByKind: counts,
            passed: violations.isEmpty
        )
    }

    public func runLVS(
        schematic: SchematicDocument,
        layout: LayoutDocument,
        designUnit: DesignUnit?,
        tech: LayoutTechDatabase? = nil,
        catalog: DeviceCatalog = .standard()
    ) -> LVSVerificationReport {
        guard let designUnit else {
            return LVSVerificationReport(
                schematicHashMatches: false,
                missingLayoutInstances: physicalComponents(in: schematic, catalog: catalog).map(\.name).sorted(),
                extraLayoutInstances: [],
                missingLayoutNets: physicalNetNames(in: schematic, catalog: catalog).sorted(),
                extraLayoutNets: [],
                danglingMappedInstanceIDs: [],
                danglingMappedNetIDs: [],
                skippedComponents: skippedComponents(in: schematic, catalog: catalog).sorted()
            )
        }

        let topCell = layout.topCellID.flatMap { layout.cell(withID: $0) }
        let topologyErrors = LayoutTopologyValidator().validate(layout: layout, topCell: topCell)
        let hashMatches = topCell != nil && designUnit.schematicHash == DesignUnit.schematicHash(for: schematic)
        let physicalComponents = physicalComponents(in: schematic, catalog: catalog)
        if !topologyErrors.isEmpty {
            return LVSVerificationReport(
                schematicHashMatches: hashMatches,
                missingLayoutInstances: physicalComponents.map(\.name).sorted(),
                extraLayoutInstances: [],
                missingLayoutNets: physicalNetNames(in: schematic, catalog: catalog).sorted(),
                extraLayoutNets: [],
                danglingMappedInstanceIDs: [],
                danglingMappedNetIDs: [],
                layoutTopologyErrors: topologyErrors,
                skippedComponents: skippedComponents(in: schematic, catalog: catalog).sorted()
            )
        }
        let rawDevices = topCell.map {
            RawLayoutDeviceExtractor(tech: tech).extract(layout: layout, topCell: $0)
        } ?? []
        let recognizedComponentIDs = topCell.map {
            recognizedLayoutComponentIDs(
                layout: layout,
                topCell: $0,
                schematic: schematic,
                rawDevices: rawDevices
            )
        } ?? []
        let physicalNetRequirements = physicalNetRequirements(in: schematic, catalog: catalog)
        let physicalNetNames = physicalNetRequirements.map(\.name)
        let fullLVS = tech.map {
            runFullLVS(
                schematic: schematic,
                layout: layout,
                tech: $0,
                designUnit: designUnit,
                catalog: catalog,
                physicalNetRequirements: physicalNetRequirements,
                rawDevices: rawDevices
            )
        }
        let actualInstanceIDs = hierarchicalInstanceIDs(layout: layout, topCell: topCell)
        let actualNetIDs = physicallyRealizedLayoutNetIDs(layout: layout, topCell: topCell)
        let actualNetNames = layoutNetNames(layout: layout, topCell: topCell)

        let missingInstances = physicalComponents
            .filter { component in
                guard let instanceID = designUnit.componentToInstance[component.id] else {
                    return !recognizedComponentIDs.contains(component.id)
                }
                return !actualInstanceIDs.contains(instanceID)
            }
            .map(\.name)
            .sorted()
        let mappedInstanceIDs = Set(designUnit.componentToInstance.values)
        let extraInstances = layoutLeafInstances(layout: layout, topCell: topCell)
            .filter { !mappedInstanceIDs.contains($0.id) }
            .map(\.name)
            .sorted()

        let mappedNetNames = Set(designUnit.netNameToLayoutNet.keys)
        let schematicNetNames = Set(physicalNetNames)
        let missingNets = schematicNetNames
            .filter { name in
                if fullLVS?.realizedNetNames.contains(name) == true {
                    return false
                }
                guard let netID = designUnit.netNameToLayoutNet[name] else {
                    return true
                }
                return !actualNetIDs.contains(netID)
            }
            .sorted()
        let extraNets = mappedNetNames
            .union(actualNetNames)
            .subtracting(schematicNetNames)
            .sorted()
        let danglingInstanceIDs = mappedInstanceIDs
            .subtracting(actualInstanceIDs)
            .sorted { $0.uuidString < $1.uuidString }
        let danglingNetIDs = Set(designUnit.netNameToLayoutNet.values)
            .subtracting(actualNetIDs)
            .sorted { $0.uuidString < $1.uuidString }
        let rawDeviceReport = compareRawLayoutDevices(
            schematic: schematic,
            catalog: catalog,
            rawDevices: rawDevices,
            tech: tech
        )
        let shouldRunConnectivityExtraction = !physicalNetRequirements.isEmpty
            || !expectedNetNamesByTerminal(schematic: schematic, physicalComponentIDs: Set(physicalComponents.map(\.id))).isEmpty

        return LVSVerificationReport(
            schematicHashMatches: hashMatches,
            missingLayoutInstances: missingInstances,
            extraLayoutInstances: extraInstances,
            missingLayoutNets: missingNets,
            extraLayoutNets: extraNets,
            danglingMappedInstanceIDs: danglingInstanceIDs,
            danglingMappedNetIDs: danglingNetIDs,
            physicalShorts: fullLVS?.shorts ?? [],
            physicalOpens: fullLVS?.opens ?? [],
            unconnectedLayoutPins: fullLVS?.unconnectedPins ?? [],
            terminalMismatches: fullLVS?.terminalMismatches ?? [],
            missingExternalLayoutPorts: fullLVS?.missingExternalPorts ?? [],
            invalidLayoutTerminals: fullLVS?.invalidTerminals ?? [],
            duplicateLayoutTerminals: fullLVS?.duplicateTerminals ?? [],
            deviceParameterMismatches: rawDeviceReport.parameterMismatches,
            duplicateLayoutDevices: rawDeviceReport.duplicateDeviceNames,
            layoutTopologyErrors: topologyErrors,
            connectivityExtractionSkipped: tech == nil && shouldRunConnectivityExtraction,
            skippedComponents: skippedComponents(in: schematic, catalog: catalog).sorted()
        )
    }

    public func runPrePEXVerification(
        schematic: SchematicDocument,
        layout: LayoutDocument,
        tech: LayoutTechDatabase,
        designUnit: DesignUnit?,
        catalog: DeviceCatalog = .standard(),
        externalSignoff: ExternalSignoffReview? = nil
    ) -> PhysicalVerificationReport {
        PhysicalVerificationReport(
            drc: runDRC(document: layout, tech: tech),
            lvs: runLVS(
                schematic: schematic,
                layout: layout,
                designUnit: designUnit,
                tech: tech,
                catalog: catalog
            ),
            externalSignoff: externalSignoff
        )
    }

    private func physicalComponents(
        in schematic: SchematicDocument,
        catalog: DeviceCatalog
    ) -> [PlacedComponent] {
        schematic.components.filter { component in
            guard let kind = catalog.device(for: component.deviceKindID) else { return false }
            return kind.category != .special
                && kind.category != .source
                && kind.category != .controlled
                && kind.category != .port
        }
    }

    private func skippedComponents(
        in schematic: SchematicDocument,
        catalog: DeviceCatalog
    ) -> [String] {
        schematic.components.compactMap { component in
            guard let kind = catalog.device(for: component.deviceKindID) else {
                return component.name
            }
            if kind.category == .source || kind.category == .controlled {
                return component.name
            }
            return nil
        }
    }

    private func physicalNetNames(
        in schematic: SchematicDocument,
        catalog: DeviceCatalog
    ) -> [String] {
        physicalNetRequirements(in: schematic, catalog: catalog).map(\.name)
    }

    private func physicalNetRequirements(
        in schematic: SchematicDocument,
        catalog: DeviceCatalog
    ) -> [PhysicalNetRequirement] {
        let physicalIDs = Set(physicalComponents(in: schematic, catalog: catalog).map(\.id))
        return NetExtractor().extract(from: schematic).compactMap { net in
            let physicalConnectionCount = net.connections.filter { physicalIDs.contains($0.componentID) }.count
            guard physicalConnectionCount > 0 else { return nil }
            return PhysicalNetRequirement(
                name: net.name,
                requiresExternalPort: physicalConnectionCount == 1 && net.connections.count > 1
            )
        }
    }

    private func physicallyRealizedLayoutNetIDs(layout: LayoutDocument, topCell: LayoutCell?) -> Set<UUID> {
        guard let topCell else { return [] }

        var ids = Set<UUID>()
        collectRealizedNetIDs(layout: layout, cell: topCell, into: &ids)
        return ids
    }

    private func layoutNetNames(layout: LayoutDocument, topCell: LayoutCell?) -> Set<String> {
        guard let topCell else { return [] }
        var names = Set<String>()
        collectLayoutNetNames(layout: layout, cell: topCell, into: &names)
        return names
    }

    private func hierarchicalInstanceIDs(layout: LayoutDocument, topCell: LayoutCell?) -> Set<UUID> {
        guard let topCell else { return [] }
        var ids = Set<UUID>()
        collectInstanceIDs(layout: layout, cell: topCell, into: &ids)
        return ids
    }

    private func layoutLeafInstances(layout: LayoutDocument, topCell: LayoutCell?) -> [LayoutInstance] {
        guard let topCell else { return [] }
        var instances: [LayoutInstance] = []
        collectLeafInstances(layout: layout, cell: topCell, into: &instances)
        return instances
    }

    private func recognizedLayoutComponentIDs(
        layout: LayoutDocument,
        topCell: LayoutCell,
        schematic: SchematicDocument,
        rawDevices: [RawLayoutDevice]
    ) -> Set<UUID> {
        let componentIDsByName = Dictionary(uniqueKeysWithValues: schematic.components.map { ($0.name, $0.id) })
        var componentIDs = Set<UUID>()
        collectRecognizedComponentIDs(
            layout: layout,
            cell: topCell,
            componentIDsByName: componentIDsByName,
            into: &componentIDs
        )
        for device in rawDevices {
            guard let componentID = componentIDsByName[device.name] else { continue }
            componentIDs.insert(componentID)
        }
        return componentIDs
    }

    private func compareRawLayoutDevices(
        schematic: SchematicDocument,
        catalog: DeviceCatalog,
        rawDevices: [RawLayoutDevice],
        tech: LayoutTechDatabase?
    ) -> RawLayoutDeviceComparison {
        let devicesByName = Dictionary(grouping: rawDevices, by: \.name)
        let schematicDeviceNames = Set(physicalComponents(in: schematic, catalog: catalog).map(\.name))
        let duplicates = devicesByName
            .filter { schematicDeviceNames.contains($0.key) && $0.value.count > 1 }
            .map(\.key)
            .sorted()
        let tolerance = max((tech?.grid ?? 0.01) * 2, 0.02)
        var mismatches: [LVSVerificationReport.DeviceParameterMismatch] = []

        for component in schematic.components {
            guard let kind = catalog.device(for: component.deviceKindID),
                  let modelType = kind.modelType,
                  modelType == "NMOS" || modelType == "PMOS",
                  let rawDevice = devicesByName[component.name]?.first else {
                continue
            }

            let expectedKind: RawLayoutDevice.Kind = modelType == "PMOS" ? .pmos : .nmos
            if rawDevice.kind != expectedKind {
                mismatches.append(LVSVerificationReport.DeviceParameterMismatch(
                    componentName: component.name,
                    parameterName: "kind",
                    expectedValue: expectedKind.numericValue,
                    actualValue: rawDevice.kind.numericValue,
                    tolerance: 0
                ))
            }

            if let expectedW = component.parameters["w"] {
                appendMismatchIfNeeded(
                    componentName: component.name,
                    parameterName: "w",
                    expectedLayoutValue: expectedW * 1e6,
                    actualLayoutValue: rawDevice.width,
                    tolerance: tolerance,
                    into: &mismatches
                )
            }
            if let expectedL = component.parameters["l"] {
                appendMismatchIfNeeded(
                    componentName: component.name,
                    parameterName: "l",
                    expectedLayoutValue: expectedL * 1e6,
                    actualLayoutValue: rawDevice.length,
                    tolerance: tolerance,
                    into: &mismatches
                )
            }
            if let expectedFingerCount = component.parameters["nf"] {
                appendMismatchIfNeeded(
                    componentName: component.name,
                    parameterName: "nf",
                    expectedLayoutValue: max(1, expectedFingerCount.rounded()),
                    actualLayoutValue: Double(rawDevice.fingerCount),
                    tolerance: 0.1,
                    into: &mismatches
                )
            }
        }
        for component in schematic.components {
            guard let kind = catalog.device(for: component.deviceKindID),
                  kind.spicePrefix == "R",
                  let rawDevice = devicesByName[component.name]?.first else {
                continue
            }
            if rawDevice.kind != .resistor {
                mismatches.append(LVSVerificationReport.DeviceParameterMismatch(
                    componentName: component.name,
                    parameterName: "kind",
                    expectedValue: RawLayoutDevice.Kind.resistor.numericValue,
                    actualValue: rawDevice.kind.numericValue,
                    tolerance: 0
                ))
            }
            if let expectedR = component.parameters["r"], let actualR = rawDevice.resistance {
                appendMismatchIfNeeded(
                    componentName: component.name,
                    parameterName: "r",
                    expectedLayoutValue: expectedR,
                    actualLayoutValue: actualR,
                    tolerance: max(abs(expectedR) * 0.01, 1e-9),
                    into: &mismatches
                )
            }
        }
        for component in schematic.components {
            guard let kind = catalog.device(for: component.deviceKindID),
                  kind.spicePrefix == "C",
                  let rawDevice = devicesByName[component.name]?.first else {
                continue
            }
            if rawDevice.kind != .capacitor {
                mismatches.append(LVSVerificationReport.DeviceParameterMismatch(
                    componentName: component.name,
                    parameterName: "kind",
                    expectedValue: RawLayoutDevice.Kind.capacitor.numericValue,
                    actualValue: rawDevice.kind.numericValue,
                    tolerance: 0
                ))
            }
            if let expectedC = component.parameters["c"], let actualC = rawDevice.capacitance {
                appendMismatchIfNeeded(
                    componentName: component.name,
                    parameterName: "c",
                    expectedLayoutValue: expectedC,
                    actualLayoutValue: actualC,
                    tolerance: max(abs(expectedC) * 0.05, 1e-18),
                    into: &mismatches
                )
            }
        }

        return RawLayoutDeviceComparison(
            parameterMismatches: mismatches.sorted {
                if $0.componentName != $1.componentName {
                    return $0.componentName < $1.componentName
                }
                return $0.parameterName < $1.parameterName
            },
            duplicateDeviceNames: duplicates
        )
    }

    private func appendMismatchIfNeeded(
        componentName: String,
        parameterName: String,
        expectedLayoutValue: Double,
        actualLayoutValue: Double,
        tolerance: Double,
        into mismatches: inout [LVSVerificationReport.DeviceParameterMismatch]
    ) {
        guard abs(expectedLayoutValue - actualLayoutValue) > tolerance else { return }
        mismatches.append(LVSVerificationReport.DeviceParameterMismatch(
            componentName: componentName,
            parameterName: parameterName,
            expectedValue: expectedLayoutValue,
            actualValue: actualLayoutValue,
            tolerance: tolerance
        ))
    }

    private func collectRecognizedComponentIDs(
        layout: LayoutDocument,
        cell: LayoutCell,
        componentIDsByName: [String: UUID],
        into componentIDs: inout Set<UUID>
    ) {
        for shape in cell.shapes {
            guard let componentName = propertyValue(
                in: shape.properties,
                keys: ["lvs.component", "lvsComponent", "component"]
            ),
                  let componentID = componentIDsByName[componentName] else {
                continue
            }
            componentIDs.insert(componentID)
        }
        for instance in cell.instances {
            guard let child = layout.cell(withID: instance.cellID) else { continue }
            collectRecognizedComponentIDs(
                layout: layout,
                cell: child,
                componentIDsByName: componentIDsByName,
                into: &componentIDs
            )
        }
    }

    private func collectRealizedNetIDs(layout: LayoutDocument, cell: LayoutCell, into ids: inout Set<UUID>) {
        ids.formUnion(cell.shapes.compactMap(\.netID))
        ids.formUnion(cell.vias.compactMap(\.netID))
        ids.formUnion(cell.pins.compactMap(\.netID))
        ids.formUnion(cell.labels.compactMap(\.netID))
        for instance in cell.instances {
            guard let child = layout.cell(withID: instance.cellID) else { continue }
            collectRealizedNetIDs(layout: layout, cell: child, into: &ids)
        }
    }

    private func collectLayoutNetNames(layout: LayoutDocument, cell: LayoutCell, into names: inout Set<String>) {
        names.formUnion(cell.nets.map(\.name))
        for instance in cell.instances {
            guard let child = layout.cell(withID: instance.cellID) else { continue }
            collectLayoutNetNames(layout: layout, cell: child, into: &names)
        }
    }

    private func collectInstanceIDs(layout: LayoutDocument, cell: LayoutCell, into ids: inout Set<UUID>) {
        for instance in cell.instances {
            ids.insert(instance.id)
            guard let child = layout.cell(withID: instance.cellID) else { continue }
            collectInstanceIDs(layout: layout, cell: child, into: &ids)
        }
    }

    private func collectLeafInstances(layout: LayoutDocument, cell: LayoutCell, into instances: inout [LayoutInstance]) {
        for instance in cell.instances {
            guard let child = layout.cell(withID: instance.cellID) else {
                instances.append(instance)
                continue
            }
            if child.instances.isEmpty {
                instances.append(instance)
            } else {
                collectLeafInstances(layout: layout, cell: child, into: &instances)
            }
        }
    }

    private func runFullLVS(
        schematic: SchematicDocument,
        layout: LayoutDocument,
        tech: LayoutTechDatabase,
        designUnit: DesignUnit,
        catalog: DeviceCatalog,
        physicalNetRequirements: [PhysicalNetRequirement],
        rawDevices: [RawLayoutDevice]
    ) -> FullLVSResult {
        guard let topCell = layout.topCellID.flatMap({ layout.cell(withID: $0) }) else {
            return FullLVSResult()
        }

        let physicalComponents = physicalComponents(in: schematic, catalog: catalog)
        let expectedByTerminal = expectedNetNamesByTerminal(
            schematic: schematic,
            physicalComponentIDs: Set(physicalComponents.map(\.id))
        )
        guard !expectedByTerminal.isEmpty else {
            return FullLVSResult()
        }

        let extraction = LayoutConnectivityExtractor().extract(
            layout: layout,
            topCell: topCell,
            tech: tech,
            componentToInstance: designUnit.componentToInstance,
            componentNamesByID: Dictionary(uniqueKeysWithValues: schematic.components.map { ($0.id, $0.name) }),
            rawDevices: rawDevices
        )
        let netNamesByID = layoutNetNamesByID(layout: layout, topCell: topCell)
        let terminalToCluster = extraction.terminalToCluster
        let clusterByID = Dictionary(uniqueKeysWithValues: extraction.clusters.map { ($0.id, $0) })
        let expectedTerminalSet = Set(expectedByTerminal.keys)

        let unconnectedPins = expectedByTerminal.keys
            .filter { terminalToCluster[$0] == nil }
            .map(makeReportTerminal)
            .sorted(by: compareTerminals)

        var expectedNetsByCluster: [Int: Set<String>] = [:]
        var terminalsByExpectedNet: [String: Set<TerminalKey>] = [:]
        var clusterIDsByExpectedNet: [String: Set<Int>] = [:]
        var terminalMismatches: [LVSVerificationReport.TerminalMismatch] = []

        for (terminal, expectedNetName) in expectedByTerminal {
            terminalsByExpectedNet[expectedNetName, default: []].insert(terminal)
            guard let clusterID = terminalToCluster[terminal],
                  let cluster = clusterByID[clusterID] else {
                continue
            }

            expectedNetsByCluster[clusterID, default: []].insert(expectedNetName)
            clusterIDsByExpectedNet[expectedNetName, default: []].insert(clusterID)

            let actualNetNames = cluster.netIDs.compactMap { netNamesByID[$0] }.sorted()
            if !actualNetNames.isEmpty, !actualNetNames.contains(expectedNetName) {
                terminalMismatches.append(LVSVerificationReport.TerminalMismatch(
                    terminal: makeReportTerminal(terminal),
                    expectedNetName: expectedNetName,
                    actualNetNames: actualNetNames
                ))
            }
        }

        let shorts = expectedNetsByCluster.values.compactMap { netNames -> LVSVerificationReport.PhysicalShort? in
            guard netNames.count > 1 else { return nil }
            let sortedNetNames = netNames.sorted()
            let terminals = expectedByTerminal
                .filter { terminal, terminalNetName in
                    sortedNetNames.contains(terminalNetName)
                        && terminalToCluster[terminal].map { expectedNetsByCluster[$0] == netNames } == true
                }
                .map { makeReportTerminal($0.key) }
                .sorted(by: compareTerminals)
            return LVSVerificationReport.PhysicalShort(netNames: sortedNetNames, terminals: terminals)
        }
        .sorted { $0.netNames.joined(separator: ",") < $1.netNames.joined(separator: ",") }

        let opens = clusterIDsByExpectedNet.compactMap { netName, clusterIDs -> LVSVerificationReport.PhysicalOpen? in
            guard clusterIDs.count > 1 else { return nil }
            let terminals = terminalsByExpectedNet[netName, default: []]
                .map(makeReportTerminal)
                .sorted(by: compareTerminals)
            return LVSVerificationReport.PhysicalOpen(
                netName: netName,
                terminals: terminals,
                physicalNetCount: clusterIDs.count
            )
        }
        .sorted { $0.netName < $1.netName }

        let externalPortRequirements = Set(
            physicalNetRequirements
                .filter(\.requiresExternalPort)
                .map(\.name)
        )
        let missingExternalPorts = externalPortRequirements.filter { netName in
            guard let clusterIDs = clusterIDsByExpectedNet[netName], clusterIDs.count == 1,
                  let clusterID = clusterIDs.first,
                  let cluster = clusterByID[clusterID] else {
                return true
            }
            return !cluster.externalPortNames.contains(netName)
        }
        .sorted()
        let extraMetadataTerminals = extraction.metadataTerminals
            .subtracting(expectedTerminalSet)
            .map(makeReportTerminal)
            .sorted(by: compareTerminals)
        let invalidTerminals = (extraction.invalidTerminals + extraMetadataTerminals)
            .sorted(by: compareTerminals)
        let duplicateTerminals = extraction.terminalClusterIDs.compactMap { terminal, clusterIDs in
            clusterIDs.count > 1 ? makeReportTerminal(terminal) : nil
        }
        .sorted(by: compareTerminals)

        return FullLVSResult(
            shorts: shorts,
            opens: opens,
            unconnectedPins: unconnectedPins,
            terminalMismatches: terminalMismatches.sorted {
                if $0.terminal.componentName != $1.terminal.componentName {
                    return $0.terminal.componentName < $1.terminal.componentName
                }
                return $0.terminal.pinName < $1.terminal.pinName
            },
            missingExternalPorts: missingExternalPorts,
            invalidTerminals: invalidTerminals,
            duplicateTerminals: duplicateTerminals,
            realizedNetNames: Set(clusterIDsByExpectedNet.keys)
        )
    }

    private func layoutNetNamesByID(layout: LayoutDocument, topCell: LayoutCell) -> [UUID: String] {
        var result: [UUID: String] = [:]
        collectLayoutNetNamesByID(layout: layout, cell: topCell, into: &result)
        return result
    }

    private func collectLayoutNetNamesByID(
        layout: LayoutDocument,
        cell: LayoutCell,
        into result: inout [UUID: String]
    ) {
        for net in cell.nets {
            result[net.id] = net.name
        }
        for instance in cell.instances {
            guard let child = layout.cell(withID: instance.cellID) else { continue }
            collectLayoutNetNamesByID(layout: layout, cell: child, into: &result)
        }
    }

    private func expectedNetNamesByTerminal(
        schematic: SchematicDocument,
        physicalComponentIDs: Set<UUID>
    ) -> [TerminalKey: String] {
        var result: [TerminalKey: String] = [:]
        let componentNames = Dictionary(uniqueKeysWithValues: schematic.components.map { ($0.id, $0.name) })
        for net in NetExtractor().extract(from: schematic) {
            for connection in net.connections where physicalComponentIDs.contains(connection.componentID) {
                guard let componentName = componentNames[connection.componentID] else { continue }
                result[TerminalKey(
                    componentID: connection.componentID,
                    componentName: componentName,
                    pinName: connection.portID
                )] = net.name
            }
        }
        return result
    }

    private func makeReportTerminal(_ terminal: TerminalKey) -> LVSVerificationReport.Terminal {
        LVSVerificationReport.Terminal(componentName: terminal.componentName, pinName: terminal.pinName)
    }

    private func compareTerminals(
        _ lhs: LVSVerificationReport.Terminal,
        _ rhs: LVSVerificationReport.Terminal
    ) -> Bool {
        if lhs.componentName != rhs.componentName {
            return lhs.componentName < rhs.componentName
        }
        return lhs.pinName < rhs.pinName
    }
}

private struct LayoutTopologyValidator: Sendable {
    func validate(layout: LayoutDocument, topCell: LayoutCell?) -> [String] {
        guard let topCell else {
            return ["Missing top cell"]
        }
        let cellIDs = Set(layout.cells.map(\.id))
        var errors: [String] = []
        for cell in layout.cells {
            for instance in cell.instances where !cellIDs.contains(instance.cellID) {
                errors.append("Missing referenced cell '\(instance.cellID.uuidString)' from instance '\(instance.name)' in cell '\(cell.name)'")
            }
        }

        var visiting: [UUID] = []
        var visited = Set<UUID>()
        detectCycles(
            layout: layout,
            cell: topCell,
            visiting: &visiting,
            visited: &visited,
            errors: &errors
        )
        return Array(Set(errors)).sorted()
    }

    private func detectCycles(
        layout: LayoutDocument,
        cell: LayoutCell,
        visiting: inout [UUID],
        visited: inout Set<UUID>,
        errors: inout [String]
    ) {
        if let cycleStart = visiting.firstIndex(of: cell.id) {
            let cycleIDs = visiting[cycleStart...] + [cell.id]
            let names = cycleIDs.map { layout.cell(withID: $0)?.name ?? $0.uuidString }
            errors.append("Hierarchy cycle: \(names.joined(separator: " -> "))")
            return
        }
        guard !visited.contains(cell.id) else { return }
        visiting.append(cell.id)
        for instance in cell.instances {
            guard let child = layout.cell(withID: instance.cellID) else { continue }
            detectCycles(
                layout: layout,
                cell: child,
                visiting: &visiting,
                visited: &visited,
                errors: &errors
            )
        }
        _ = visiting.popLast()
        visited.insert(cell.id)
    }
}

private struct FullLVSResult: Sendable, Hashable {
    var shorts: [LVSVerificationReport.PhysicalShort] = []
    var opens: [LVSVerificationReport.PhysicalOpen] = []
    var unconnectedPins: [LVSVerificationReport.Terminal] = []
    var terminalMismatches: [LVSVerificationReport.TerminalMismatch] = []
    var missingExternalPorts: [String] = []
    var invalidTerminals: [LVSVerificationReport.Terminal] = []
    var duplicateTerminals: [LVSVerificationReport.Terminal] = []
    var realizedNetNames: Set<String> = []
}

private struct PhysicalNetRequirement: Sendable, Hashable {
    let name: String
    let requiresExternalPort: Bool
}

private struct RawLayoutDevice: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case nmos
        case pmos
        case resistor
        case capacitor

        var numericValue: Double {
            switch self {
            case .nmos: return 0
            case .pmos: return 1
            case .resistor: return 2
            case .capacitor: return 3
            }
        }
    }

    let name: String
    let kind: Kind
    let width: Double
    let length: Double
    let fingerCount: Int
    let resistance: Double?
    let capacitance: Double?
    let terminals: [RawLayoutTerminal]
}

private struct RawLayoutTerminal: Sendable, Hashable {
    let pinName: String
    let layer: LayoutLayerID
    let geometry: LayoutGeometry
}

private struct RawLayoutDeviceComparison: Sendable, Hashable {
    let parameterMismatches: [LVSVerificationReport.DeviceParameterMismatch]
    let duplicateDeviceNames: [String]
}

private struct TerminalKey: Sendable, Hashable {
    let componentID: UUID
    let componentName: String
    let pinName: String
}

private struct ComponentBinding: Sendable, Hashable {
    let componentID: UUID
    let componentName: String
}

private enum LayoutSemanticLayer: Sendable, Hashable, CaseIterable {
    case nwell
    case active
    case poly
    case nimp
    case pimp
    case resi
    case contact
    case m1
    case m2
    case via1

    var canonicalID: LayoutLayerID {
        switch self {
        case .nwell: return LayoutLayerID(name: "NWELL", purpose: "drawing")
        case .active: return LayoutLayerID(name: "ACTIVE", purpose: "drawing")
        case .poly: return LayoutLayerID(name: "POLY", purpose: "drawing")
        case .nimp: return LayoutLayerID(name: "NIMP", purpose: "drawing")
        case .pimp: return LayoutLayerID(name: "PIMP", purpose: "drawing")
        case .resi: return LayoutLayerID(name: "RESI", purpose: "drawing")
        case .contact: return LayoutLayerID(name: "CONTACT", purpose: "cut")
        case .m1: return LayoutLayerID(name: "M1", purpose: "drawing")
        case .m2: return LayoutLayerID(name: "M2", purpose: "drawing")
        case .via1: return LayoutLayerID(name: "VIA1", purpose: "cut")
        }
    }

    var nameAliases: Set<String> {
        switch self {
        case .nwell: return ["NWELL", "N-WELL", "N_WELL"]
        case .active: return ["ACTIVE", "DIFF", "DIFFUSION", "OD", "AA", "RX"]
        case .poly: return ["POLY", "POLYSILICON", "PO", "GATE"]
        case .nimp: return ["NIMP", "NPLUS", "N+", "NSD", "N_IMPLANT"]
        case .pimp: return ["PIMP", "PPLUS", "P+", "PSD", "P_IMPLANT"]
        case .resi: return ["RESI", "RES", "RPO", "RESISTOR"]
        case .contact: return ["CONTACT", "CONT", "CA", "CO"]
        case .m1: return ["M1", "MET1", "METAL1", "LI1"]
        case .m2: return ["M2", "MET2", "METAL2"]
        case .via1: return ["VIA1", "V1", "VIA"]
        }
    }
}

private struct LayoutLayerAliasResolver: Sendable, Hashable {
    private let aliasesBySemanticLayer: [LayoutSemanticLayer: Set<LayoutLayerID>]
    private let semanticLayerByAlias: [LayoutLayerID: LayoutSemanticLayer]

    init(tech: LayoutTechDatabase?) {
        var aliases: [LayoutSemanticLayer: Set<LayoutLayerID>] = [:]
        for semanticLayer in LayoutSemanticLayer.allCases {
            aliases[semanticLayer, default: []].insert(semanticLayer.canonicalID)
        }
        for layer in tech?.layers ?? [] {
            guard let semanticLayer = Self.semanticLayer(for: layer.id) else { continue }
            aliases[semanticLayer, default: []].insert(layer.id)
            aliases[semanticLayer, default: []].insert(LayoutLayerID(
                name: "L\(layer.gdsLayer)",
                purpose: "D\(layer.gdsDatatype)"
            ))
        }
        var reverse: [LayoutLayerID: LayoutSemanticLayer] = [:]
        for (semanticLayer, layerAliases) in aliases {
            for alias in layerAliases {
                reverse[alias] = semanticLayer
            }
        }
        self.aliasesBySemanticLayer = aliases
        self.semanticLayerByAlias = reverse
    }

    func matches(_ layer: LayoutLayerID, _ semanticLayer: LayoutSemanticLayer) -> Bool {
        if aliasesBySemanticLayer[semanticLayer, default: []].contains(layer) {
            return true
        }
        return Self.semanticLayer(for: layer) == semanticLayer
    }

    func normalize(_ layer: LayoutLayerID) -> LayoutLayerID {
        if let semanticLayer = semanticLayerByAlias[layer] {
            return semanticLayer.canonicalID
        }
        return Self.semanticLayer(for: layer)?.canonicalID ?? layer
    }

    private static func semanticLayer(for layer: LayoutLayerID) -> LayoutSemanticLayer? {
        let normalizedName = layer.name
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return LayoutSemanticLayer.allCases.first { semanticLayer in
            semanticLayer.nameAliases.contains(normalizedName)
        }
    }
}

private struct LayoutConnectivityCluster: Sendable, Hashable {
    let id: Int
    let terminals: Set<TerminalKey>
    let netIDs: Set<UUID>
    let externalPortNames: Set<String>
}

private struct LayoutConnectivityExtraction: Sendable, Hashable {
    let clusters: [LayoutConnectivityCluster]
    let terminalToCluster: [TerminalKey: Int]
    let terminalClusterIDs: [TerminalKey: Set<Int>]
    let metadataTerminals: Set<TerminalKey>
    let invalidTerminals: [LVSVerificationReport.Terminal]
}

private struct LayoutConnectivityExtractor: Sendable {
    func extract(
        layout: LayoutDocument,
        topCell: LayoutCell,
        tech: LayoutTechDatabase,
        componentToInstance: [UUID: UUID],
        componentNamesByID: [UUID: String],
        rawDevices: [RawLayoutDevice]
    ) -> LayoutConnectivityExtraction {
        let componentByInstanceID = componentByInstanceID(
            componentToInstance: componentToInstance,
            componentNamesByID: componentNamesByID
        )
        let mappedComponentNames = Set(componentToInstance.keys.compactMap { componentNamesByID[$0] })
        let layerResolver = LayoutLayerAliasResolver(tech: tech)
        var elements: [ConnectivityElement] = []
        let componentIDsByName = Dictionary(uniqueKeysWithValues: componentNamesByID.map { ($0.value, $0.key) })
        var metadataTerminals = Set<TerminalKey>()
        var invalidTerminals: [LVSVerificationReport.Terminal] = []

        appendCellElements(
            layout: layout,
            cell: topCell,
            tech: tech,
            transforms: [],
            isTopLevel: true,
            componentByInstanceID: componentByInstanceID,
            componentIDsByName: componentIDsByName,
            layerResolver: layerResolver,
            metadataTerminals: &metadataTerminals,
            invalidTerminals: &invalidTerminals,
            elements: &elements
        )
        appendRawDeviceTerminals(
            rawDevices: rawDevices,
            mappedComponentNames: mappedComponentNames,
            componentIDsByName: componentIDsByName,
            layerResolver: layerResolver,
            elements: &elements
        )

        guard !elements.isEmpty else {
            return LayoutConnectivityExtraction(
                clusters: [],
                terminalToCluster: [:],
                terminalClusterIDs: [:],
                metadataTerminals: metadataTerminals,
                invalidTerminals: invalidTerminals.sorted(by: compareTerminals)
            )
        }

        var unionFind = IndexedUnionFind(count: elements.count)
        for i in 0..<(elements.count - 1) {
            for j in (i + 1)..<elements.count {
                if connects(elements[i], elements[j], tech: tech) {
                    unionFind.union(i, j)
                }
            }
        }

        var terminalsByRoot: [Int: Set<TerminalKey>] = [:]
        var netIDsByRoot: [Int: Set<UUID>] = [:]
        var externalPortsByRoot: [Int: Set<String>] = [:]
        for index in elements.indices {
            let root = unionFind.find(index)
            if let terminal = elements[index].terminal {
                terminalsByRoot[root, default: []].insert(terminal)
            }
            if let netID = elements[index].netID {
                netIDsByRoot[root, default: []].insert(netID)
            }
            if let externalPortName = elements[index].externalPortName {
                externalPortsByRoot[root, default: []].insert(externalPortName)
            }
        }

        let roots = Set(elements.indices.map { unionFind.find($0) }).sorted()
        var clusterIDByRoot: [Int: Int] = [:]
        var clusters: [LayoutConnectivityCluster] = []
        for (clusterID, root) in roots.enumerated() {
            clusterIDByRoot[root] = clusterID
            clusters.append(LayoutConnectivityCluster(
                id: clusterID,
                terminals: terminalsByRoot[root, default: []],
                netIDs: netIDsByRoot[root, default: []],
                externalPortNames: externalPortsByRoot[root, default: []]
            ))
        }

        var terminalToCluster: [TerminalKey: Int] = [:]
        var terminalClusterIDs: [TerminalKey: Set<Int>] = [:]
        for cluster in clusters {
            for terminal in cluster.terminals {
                terminalToCluster[terminal] = cluster.id
                terminalClusterIDs[terminal, default: []].insert(cluster.id)
            }
        }

        return LayoutConnectivityExtraction(
            clusters: clusters,
            terminalToCluster: terminalToCluster,
            terminalClusterIDs: terminalClusterIDs,
            metadataTerminals: metadataTerminals,
            invalidTerminals: invalidTerminals.sorted(by: compareTerminals)
        )
    }

    private func componentByInstanceID(
        componentToInstance: [UUID: UUID],
        componentNamesByID: [UUID: String]
    ) -> [UUID: ComponentBinding] {
        var result: [UUID: ComponentBinding] = [:]
        for (componentID, instanceID) in componentToInstance {
            guard let componentName = componentNamesByID[componentID] else { continue }
            result[instanceID] = ComponentBinding(componentID: componentID, componentName: componentName)
        }
        return result
    }

    private func appendCellElements(
        layout: LayoutDocument,
        cell: LayoutCell,
        tech: LayoutTechDatabase,
        transforms: [LayoutTransform],
        isTopLevel: Bool,
        componentByInstanceID: [UUID: ComponentBinding],
        componentIDsByName: [String: UUID],
        layerResolver: LayoutLayerAliasResolver,
        metadataTerminals: inout Set<TerminalKey>,
        invalidTerminals: inout [LVSVerificationReport.Terminal],
        elements: inout [ConnectivityElement]
    ) {
        for shape in cell.shapes {
            let terminal = recognizedTerminal(
                from: shape.properties,
                componentIDsByName: componentIDsByName,
                invalidTerminals: &invalidTerminals
            )
            if let terminal {
                metadataTerminals.insert(terminal)
            }
            let bridge = bridgeLayers(forCutLayer: shape.layer, tech: tech, layerResolver: layerResolver)
            elements.append(ConnectivityElement(
                layer: layerResolver.normalize(shape.layer),
                geometry: transformed(shape.geometry, by: transforms),
                terminal: terminal,
                netID: shape.netID,
                isVia: bridge != nil,
                viaDefinitionID: nil,
                viaTopLayer: bridge?.top,
                viaBottomLayer: bridge?.bottom,
                externalPortName: nil
            ))
        }

        for pin in cell.pins {
            elements.append(ConnectivityElement(
                layer: layerResolver.normalize(pin.layer),
                geometry: transformed(pinGeometry(pin.position, size: pin.size), by: transforms),
                terminal: nil,
                netID: pin.netID,
                isVia: false,
                viaDefinitionID: nil,
                viaTopLayer: nil,
                viaBottomLayer: nil,
                externalPortName: isTopLevel ? pin.name : nil
            ))
        }

        for label in cell.labels {
            elements.append(ConnectivityElement(
                layer: layerResolver.normalize(label.layer),
                geometry: transformed(labelGeometry(label.position), by: transforms),
                terminal: nil,
                netID: label.netID,
                isVia: false,
                viaDefinitionID: nil,
                viaTopLayer: nil,
                viaBottomLayer: nil,
                externalPortName: isTopLevel ? label.text : nil
            ))
        }

        for via in cell.vias {
            let viaDefinition = tech.viaDefinition(for: via.viaDefinitionID)
            elements.append(ConnectivityElement(
                layer: layerResolver.normalize(viaDefinition?.cutLayer ?? LayoutLayerID(name: via.viaDefinitionID, purpose: "cut")),
                geometry: transformed(viaGeometry(via, tech: tech), by: transforms),
                terminal: nil,
                netID: via.netID,
                isVia: true,
                viaDefinitionID: via.viaDefinitionID,
                viaTopLayer: viaDefinition.map { layerResolver.normalize($0.topLayer) },
                viaBottomLayer: viaDefinition.map { layerResolver.normalize($0.bottomLayer) },
                externalPortName: nil
            ))
        }

        for instance in cell.instances {
            guard let child = layout.cell(withID: instance.cellID) else { continue }
            let childTransforms = transforms + [instance.transform]
            if let binding = componentByInstanceID[instance.id] {
                appendMappedInstancePins(
                    cell: child,
                    transforms: childTransforms,
                    binding: binding,
                    layerResolver: layerResolver,
                    elements: &elements
                )
            } else {
                appendCellElements(
                    layout: layout,
                    cell: child,
                    tech: tech,
                    transforms: childTransforms,
                    isTopLevel: false,
                    componentByInstanceID: componentByInstanceID,
                    componentIDsByName: componentIDsByName,
                    layerResolver: layerResolver,
                    metadataTerminals: &metadataTerminals,
                    invalidTerminals: &invalidTerminals,
                    elements: &elements
                )
            }
        }
    }

    private func appendMappedInstancePins(
        cell: LayoutCell,
        transforms: [LayoutTransform],
        binding: ComponentBinding,
        layerResolver: LayoutLayerAliasResolver,
        elements: inout [ConnectivityElement]
    ) {
        for pin in cell.pins {
            elements.append(ConnectivityElement(
                layer: layerResolver.normalize(pin.layer),
                geometry: transformed(pinGeometry(pin.position, size: pin.size), by: transforms),
                terminal: TerminalKey(
                    componentID: binding.componentID,
                    componentName: binding.componentName,
                    pinName: pin.name
                ),
                netID: pin.netID,
                isVia: false,
                viaDefinitionID: nil,
                viaTopLayer: nil,
                viaBottomLayer: nil,
                externalPortName: nil
            ))
        }
    }

    private func appendRawDeviceTerminals(
        rawDevices: [RawLayoutDevice],
        mappedComponentNames: Set<String>,
        componentIDsByName: [String: UUID],
        layerResolver: LayoutLayerAliasResolver,
        elements: inout [ConnectivityElement]
    ) {
        for device in rawDevices {
            guard !mappedComponentNames.contains(device.name) else { continue }
            guard let componentID = componentIDsByName[device.name] else { continue }
            for terminal in device.terminals {
                elements.append(ConnectivityElement(
                    layer: layerResolver.normalize(terminal.layer),
                    geometry: terminal.geometry,
                    terminal: TerminalKey(
                        componentID: componentID,
                        componentName: device.name,
                        pinName: terminal.pinName
                    ),
                    netID: nil,
                    isVia: false,
                    viaDefinitionID: nil,
                    viaTopLayer: nil,
                    viaBottomLayer: nil,
                    externalPortName: nil
                ))
            }
        }
    }

    private func recognizedTerminal(
        from properties: [String: String],
        componentIDsByName: [String: UUID],
        invalidTerminals: inout [LVSVerificationReport.Terminal]
    ) -> TerminalKey? {
        let componentName = propertyValue(
            in: properties,
            keys: ["lvs.component", "lvsComponent", "component"]
        )
        let pinName = propertyValue(
            in: properties,
            keys: ["lvs.pin", "lvsPin", "pin"]
        )
        guard componentName != nil || pinName != nil else {
            return nil
        }
        guard let componentName,
              let pinName,
              let componentID = componentIDsByName[componentName] else {
            invalidTerminals.append(LVSVerificationReport.Terminal(
                componentName: componentName ?? "<missing>",
                pinName: pinName ?? "<missing>"
            ))
            return nil
        }
        return TerminalKey(componentID: componentID, componentName: componentName, pinName: pinName)
    }

    private func pinGeometry(_ center: LayoutPoint, size: LayoutSize) -> LayoutGeometry {
        .rect(LayoutRect(
            origin: LayoutPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            size: size
        ))
    }

    private func labelGeometry(_ position: LayoutPoint) -> LayoutGeometry {
        .rect(LayoutRect(
            origin: LayoutPoint(x: position.x - 0.005, y: position.y - 0.005),
            size: LayoutSize(width: 0.01, height: 0.01)
        ))
    }

    private func viaGeometry(_ via: LayoutVia, tech: LayoutTechDatabase) -> LayoutGeometry {
        let size = tech.viaDefinition(for: via.viaDefinitionID)?.cutSize
            ?? LayoutSize(width: 0.01, height: 0.01)
        return .rect(LayoutRect(
            origin: LayoutPoint(x: via.position.x - size.width / 2, y: via.position.y - size.height / 2),
            size: size
        ))
    }

    private func bridgeLayers(
        forCutLayer layer: LayoutLayerID,
        tech: LayoutTechDatabase,
        layerResolver: LayoutLayerAliasResolver
    ) -> (top: LayoutLayerID, bottom: LayoutLayerID)? {
        let normalizedLayer = layerResolver.normalize(layer)
        if let via = tech.vias.first(where: { layerResolver.normalize($0.cutLayer) == normalizedLayer }) {
            return (
                top: layerResolver.normalize(via.topLayer),
                bottom: layerResolver.normalize(via.bottomLayer)
            )
        }
        if let contact = tech.contacts.first(where: { layerResolver.normalize($0.cutLayer) == normalizedLayer }) {
            return (
                top: layerResolver.normalize(contact.topLayer),
                bottom: layerResolver.normalize(contact.bottomLayer)
            )
        }
        return nil
    }

    private func transformed(_ geometry: LayoutGeometry, by transforms: [LayoutTransform]) -> LayoutGeometry {
        var result = geometry
        for transform in transforms {
            result = result.transformed(by: transform)
        }
        return result
    }

    private func connects(_ lhs: ConnectivityElement, _ rhs: ConnectivityElement, tech: LayoutTechDatabase) -> Bool {
        if lhs.isVia || rhs.isVia {
            return viaConnects(lhs, rhs, tech: tech)
        }
        guard lhs.layer == rhs.layer else { return false }
        return geometriesTouch(lhs.geometry, rhs.geometry)
    }

    private func viaConnects(_ lhs: ConnectivityElement, _ rhs: ConnectivityElement, tech: LayoutTechDatabase) -> Bool {
        guard lhs.isVia != rhs.isVia else {
            return false
        }
        let viaElement = lhs.isVia ? lhs : rhs
        let conductor = lhs.isVia ? rhs : lhs
        let topLayer: LayoutLayerID?
        let bottomLayer: LayoutLayerID?
        if let explicitTop = viaElement.viaTopLayer, let explicitBottom = viaElement.viaBottomLayer {
            topLayer = explicitTop
            bottomLayer = explicitBottom
        } else if let viaID = viaElement.viaDefinitionID,
                  let viaDefinition = tech.viaDefinition(for: viaID) {
            topLayer = viaDefinition.topLayer
            bottomLayer = viaDefinition.bottomLayer
        } else {
            topLayer = nil
            bottomLayer = nil
        }
        guard conductor.layer == topLayer || conductor.layer == bottomLayer else {
            return false
        }
        return geometriesTouch(viaElement.geometry, conductor.geometry)
    }

    private func geometriesTouch(_ lhs: LayoutGeometry, _ rhs: LayoutGeometry) -> Bool {
        let leftBox = LayoutGeometryAnalysis.boundingBox(for: lhs)
        let rightBox = LayoutGeometryAnalysis.boundingBox(for: rhs)
        guard leftBox.intersects(rightBox) else { return false }
        if LayoutGeometryAnalysis.intersects(lhs, rhs) {
            return true
        }
        if LayoutGeometryAnalysis.contains(leftBox.center, in: rhs) {
            return true
        }
        if LayoutGeometryAnalysis.contains(rightBox.center, in: lhs) {
            return true
        }
        return false
    }

    private func compareTerminals(
        _ lhs: LVSVerificationReport.Terminal,
        _ rhs: LVSVerificationReport.Terminal
    ) -> Bool {
        if lhs.componentName != rhs.componentName {
            return lhs.componentName < rhs.componentName
        }
        return lhs.pinName < rhs.pinName
    }
}

private struct ConnectivityElement: Sendable, Hashable {
    let layer: LayoutLayerID
    let geometry: LayoutGeometry
    let terminal: TerminalKey?
    let netID: UUID?
    let isVia: Bool
    let viaDefinitionID: String?
    let viaTopLayer: LayoutLayerID?
    let viaBottomLayer: LayoutLayerID?
    let externalPortName: String?
}

private func propertyValue(in properties: [String: String], keys: [String]) -> String? {
    for key in keys {
        if let value = properties[key], !value.isEmpty {
            return value
        }
    }
    return nil
}

private struct RawLayoutDeviceExtractor: Sendable {
    private struct ShapeRecord: Sendable, Hashable {
        let layer: LayoutLayerID
        let geometry: LayoutGeometry
    }

    private struct LabelRecord: Sendable, Hashable {
        let text: String
        let position: LayoutPoint
    }

    private let layerResolver: LayoutLayerAliasResolver
    private let resistorSheetResistance = 200.0
    private let capacitorDensity = 8.6e-15

    init(tech: LayoutTechDatabase?) {
        self.layerResolver = LayoutLayerAliasResolver(tech: tech)
    }

    func extract(layout: LayoutDocument, topCell: LayoutCell) -> [RawLayoutDevice] {
        var shapes: [ShapeRecord] = []
        var labels: [LabelRecord] = []
        collect(layout: layout, cell: topCell, transforms: [], shapes: &shapes, labels: &labels)

        let actives = shapes.filter { layerResolver.matches($0.layer, .active) }
        let polys = shapes.filter { layerResolver.matches($0.layer, .poly) }
        let nimplants = shapes.filter { layerResolver.matches($0.layer, .nimp) }
        let pimplants = shapes.filter { layerResolver.matches($0.layer, .pimp) }
        let nwells = shapes.filter { layerResolver.matches($0.layer, .nwell) }
        let resis = shapes.filter { layerResolver.matches($0.layer, .resi) }
        let m1Shapes = shapes.filter { layerResolver.matches($0.layer, .m1) }

        var devices: [RawLayoutDevice] = []
        devices.append(contentsOf: extractResistors(resis: resis, polys: polys, m1Shapes: m1Shapes, labels: labels))
        devices.append(contentsOf: extractCapacitors(actives: actives, polys: polys, m1Shapes: m1Shapes, labels: labels))
        for active in actives {
            let activeBox = LayoutGeometryAnalysis.boundingBox(for: active.geometry)
            if isCapacitorActive(activeBox: activeBox, polys: polys, labels: labels) {
                continue
            }
            let channels = polys.compactMap { poly -> (polyBox: LayoutRect, channel: LayoutRect)? in
                let polyBox = LayoutGeometryAnalysis.boundingBox(for: poly.geometry)
                guard let channel = positiveIntersection(activeBox, polyBox) else { return nil }
                return (polyBox, channel)
            }
            guard !channels.isEmpty else { continue }
            devices.append(contentsOf: extractMOSDevices(
                activeBox: activeBox,
                channels: channels,
                nimplants: nimplants,
                pimplants: pimplants,
                nwells: nwells,
                m1Shapes: m1Shapes,
                labels: labels
            ))
        }
        return devices
    }

    private func extractMOSDevices(
        activeBox: LayoutRect,
        channels: [(polyBox: LayoutRect, channel: LayoutRect)],
        nimplants: [ShapeRecord],
        pimplants: [ShapeRecord],
        nwells: [ShapeRecord],
        m1Shapes: [ShapeRecord],
        labels: [LabelRecord]
    ) -> [RawLayoutDevice] {
        let labelsInside = componentLabels(for: activeBox, labels: labels)
        guard !labelsInside.isEmpty else { return [] }

        let groupedChannels: [(name: String, channels: [(polyBox: LayoutRect, channel: LayoutRect)])]
        if labelsInside.count == 1, let label = labelsInside.first {
            groupedChannels = [(label.text, channels)]
        } else {
            let grouped = Dictionary(grouping: channels) { channel in
                nearestLabel(to: channel.channel.center, labels: labelsInside)?.text ?? labelsInside[0].text
            }
            groupedChannels = grouped
                .map { (name: $0.key, channels: $0.value) }
                .sorted { $0.name < $1.name }
        }

        return groupedChannels.compactMap { group -> RawLayoutDevice? in
            guard let firstChannel = group.channels.first?.channel,
                  let mergedPolyBox = mergeRects(group.channels.map(\.polyBox)),
                  let mergedChannelBox = mergeRects(group.channels.map(\.channel)),
                  let kind = classifyMOS(
                    channel: firstChannel,
                    nimplants: nimplants,
                    pimplants: pimplants,
                    nwells: nwells
                  ) else {
                return nil
            }
            return RawLayoutDevice(
                name: group.name,
                kind: kind,
                width: mergedChannelBox.size.height,
                length: group.channels.map(\.channel.size.width).reduce(0, +) / Double(group.channels.count),
                fingerCount: group.channels.count,
                resistance: nil,
                capacitance: nil,
                terminals: mosTerminals(
                    activeBox: activeBox,
                    polyBox: mergedPolyBox,
                    channel: mergedChannelBox,
                    allChannels: channels.map(\.channel),
                    m1Shapes: m1Shapes
                )
            )
        }
    }

    private func extractResistors(
        resis: [ShapeRecord],
        polys: [ShapeRecord],
        m1Shapes: [ShapeRecord],
        labels: [LabelRecord]
    ) -> [RawLayoutDevice] {
        var devices: [RawLayoutDevice] = []
        for resi in resis {
            let resiBox = LayoutGeometryAnalysis.boundingBox(for: resi.geometry)
            guard let poly = polys.first(where: {
                LayoutGeometryAnalysis.boundingBox(for: $0.geometry).intersects(resiBox)
            }) else {
                continue
            }
            let polyBox = LayoutGeometryAnalysis.boundingBox(for: poly.geometry)
            guard let name = componentName(for: polyBox, labels: labels) else { continue }
            let body = positiveIntersection(polyBox, resiBox) ?? polyBox
            let width = body.size.height
            let length = body.size.width
            guard width > 0 else { continue }
            devices.append(RawLayoutDevice(
                name: name,
                kind: .resistor,
                width: width,
                length: length,
                fingerCount: 1,
                resistance: resistorSheetResistance * length / width,
                capacitance: nil,
                terminals: resistorTerminals(polyBox: polyBox, m1Shapes: m1Shapes)
            ))
        }
        return devices
    }

    private func extractCapacitors(
        actives: [ShapeRecord],
        polys: [ShapeRecord],
        m1Shapes: [ShapeRecord],
        labels: [LabelRecord]
    ) -> [RawLayoutDevice] {
        var devices: [RawLayoutDevice] = []
        for active in actives {
            let activeBox = LayoutGeometryAnalysis.boundingBox(for: active.geometry)
            guard let name = capacitorName(for: activeBox, labels: labels) else { continue }
            let overlaps = polys.compactMap { poly -> (polyBox: LayoutRect, overlap: LayoutRect)? in
                let polyBox = LayoutGeometryAnalysis.boundingBox(for: poly.geometry)
                guard let overlap = positiveIntersection(activeBox, polyBox) else { return nil }
                return (polyBox, overlap)
            }
            guard let largestOverlap = overlaps.max(by: {
                $0.overlap.size.width * $0.overlap.size.height < $1.overlap.size.width * $1.overlap.size.height
            }) else {
                continue
            }
            let area = largestOverlap.overlap.size.width * largestOverlap.overlap.size.height
            guard area > 0 else { continue }
            devices.append(RawLayoutDevice(
                name: name,
                kind: .capacitor,
                width: largestOverlap.overlap.size.height,
                length: largestOverlap.overlap.size.width,
                fingerCount: 1,
                resistance: nil,
                capacitance: capacitorDensity * area,
                terminals: capacitorTerminals(
                    activeBox: activeBox,
                    polyBox: largestOverlap.polyBox,
                    overlapBox: largestOverlap.overlap,
                    m1Shapes: m1Shapes
                )
            ))
        }
        return devices
    }

    private func isCapacitorActive(
        activeBox: LayoutRect,
        polys: [ShapeRecord],
        labels: [LabelRecord]
    ) -> Bool {
        guard capacitorName(for: activeBox, labels: labels) != nil else { return false }
        return polys.contains { poly in
            positiveIntersection(activeBox, LayoutGeometryAnalysis.boundingBox(for: poly.geometry)) != nil
        }
    }

    private func collect(
        layout: LayoutDocument,
        cell: LayoutCell,
        transforms: [LayoutTransform],
        shapes: inout [ShapeRecord],
        labels: inout [LabelRecord]
    ) {
        for shape in cell.shapes {
            shapes.append(ShapeRecord(
                layer: shape.layer,
                geometry: transformed(shape.geometry, by: transforms)
            ))
        }
        for label in cell.labels {
            labels.append(LabelRecord(
                text: label.text,
                position: transformed(label.position, by: transforms)
            ))
        }
        for instance in cell.instances {
            guard let child = layout.cell(withID: instance.cellID) else { continue }
            collect(
                layout: layout,
                cell: child,
                transforms: transforms + [instance.transform],
                shapes: &shapes,
                labels: &labels
            )
        }
    }

    private func componentName(for activeBox: LayoutRect, labels: [LabelRecord]) -> String? {
        componentLabels(for: activeBox, labels: labels).first?.text
    }

    private func capacitorName(for activeBox: LayoutRect, labels: [LabelRecord]) -> String? {
        componentLabels(for: activeBox, labels: labels)
            .first { $0.text.uppercased().hasPrefix("C") }?
            .text
    }

    private func componentLabels(for activeBox: LayoutRect, labels: [LabelRecord]) -> [LabelRecord] {
        labels
            .filter { activeBox.contains($0.position) && !$0.text.isEmpty }
            .sorted { lhs, rhs in
                LayoutGeometryAnalysis.distance(lhs.position, activeBox.center)
                    < LayoutGeometryAnalysis.distance(rhs.position, activeBox.center)
            }
    }

    private func nearestLabel(to point: LayoutPoint, labels: [LabelRecord]) -> LabelRecord? {
        labels.min {
            LayoutGeometryAnalysis.distance($0.position, point)
                < LayoutGeometryAnalysis.distance($1.position, point)
        }
    }

    private func classifyMOS(
        channel: LayoutRect,
        nimplants: [ShapeRecord],
        pimplants: [ShapeRecord],
        nwells: [ShapeRecord]
    ) -> RawLayoutDevice.Kind? {
        let center = channel.center
        let inPImplant = pimplants.contains {
            LayoutGeometryAnalysis.contains(center, in: $0.geometry)
        }
        let inNImplant = nimplants.contains {
            LayoutGeometryAnalysis.contains(center, in: $0.geometry)
        }
        let inNWell = nwells.contains {
            LayoutGeometryAnalysis.contains(center, in: $0.geometry)
        }
        if inPImplant || inNWell {
            return .pmos
        }
        if inNImplant {
            return .nmos
        }
        return nil
    }

    private func mosTerminals(
        activeBox: LayoutRect,
        polyBox: LayoutRect,
        channel: LayoutRect,
        allChannels: [LayoutRect],
        m1Shapes: [ShapeRecord]
    ) -> [RawLayoutTerminal] {
        let localM1Shapes = m1Shapes.filter { shape in
            let rect = LayoutGeometryAnalysis.boundingBox(for: shape.geometry)
            return
                rect.minX >= activeBox.minX - 0.001 && rect.maxX <= activeBox.maxX + 0.001
        }
        let sortedChannels = allChannels.sorted { $0.minX < $1.minX }
        let previousChannel = sortedChannels.last { $0.maxX <= channel.minX && $0 != channel }
        let nextChannel = sortedChannels.first { $0.minX >= channel.maxX && $0 != channel }
        let leftTerminalBoundary = previousChannel?.maxX ?? activeBox.minX
        let rightTerminalBoundary = nextChannel?.minX ?? activeBox.maxX
        var terminals: [RawLayoutTerminal] = []
        if let source = terminal(pinName: "source", shapes: localM1Shapes.filter {
            let rect = LayoutGeometryAnalysis.boundingBox(for: $0.geometry)
            return rect.intersects(activeBox)
                && rect.center.x < channel.minX
                && rect.center.x >= leftTerminalBoundary
        }) {
            terminals.append(source)
        }
        if let drain = terminal(pinName: "drain", shapes: localM1Shapes.filter {
            let rect = LayoutGeometryAnalysis.boundingBox(for: $0.geometry)
            return rect.intersects(activeBox)
                && rect.center.x > channel.maxX
                && rect.center.x <= rightTerminalBoundary
        }) {
            terminals.append(drain)
        }
        if let gate = terminal(pinName: "gate", shapes: localM1Shapes.filter {
            let rect = LayoutGeometryAnalysis.boundingBox(for: $0.geometry)
            return rect.intersects(polyBox)
                && !rect.intersects(channel)
                && (rect.maxY <= activeBox.minY || rect.minY >= activeBox.maxY)
        }) {
            terminals.append(gate)
        }
        if let bulk = terminal(pinName: "bulk", shapes: localM1Shapes.filter {
            let rect = LayoutGeometryAnalysis.boundingBox(for: $0.geometry)
            return !rect.intersects(activeBox)
                && !rect.intersects(polyBox)
                && rangesOverlap(rect.minX, rect.maxX, activeBox.minX, activeBox.maxX)
                && (rect.maxY <= activeBox.minY || rect.minY >= activeBox.maxY)
        }) {
            terminals.append(bulk)
        }
        return terminals
    }

    private func resistorTerminals(polyBox: LayoutRect, m1Shapes: [ShapeRecord]) -> [RawLayoutTerminal] {
        var terminals: [RawLayoutTerminal] = []
        if let neg = terminal(pinName: "neg", shapes: m1Shapes.filter {
            let rect = LayoutGeometryAnalysis.boundingBox(for: $0.geometry)
            return rect.intersects(polyBox) && rect.center.x <= polyBox.center.x
        }) {
            terminals.append(neg)
        }
        if let pos = terminal(pinName: "pos", shapes: m1Shapes.filter {
            let rect = LayoutGeometryAnalysis.boundingBox(for: $0.geometry)
            return rect.intersects(polyBox) && rect.center.x > polyBox.center.x
        }) {
            terminals.append(pos)
        }
        return terminals
    }

    private func capacitorTerminals(
        activeBox: LayoutRect,
        polyBox: LayoutRect,
        overlapBox: LayoutRect,
        m1Shapes: [ShapeRecord]
    ) -> [RawLayoutTerminal] {
        var terminals: [RawLayoutTerminal] = []
        if let neg = terminal(pinName: "neg", shapes: m1Shapes.filter {
            let rect = LayoutGeometryAnalysis.boundingBox(for: $0.geometry)
            return rect.intersects(activeBox)
                && !rect.intersects(overlapBox)
                && rect.center.x < overlapBox.center.x
        }) {
            terminals.append(neg)
        }
        if let pos = terminal(pinName: "pos", shapes: m1Shapes.filter {
            let rect = LayoutGeometryAnalysis.boundingBox(for: $0.geometry)
            return rect.intersects(polyBox)
                && !rect.intersects(overlapBox)
                && rect.center.x > overlapBox.center.x
        }) {
            terminals.append(pos)
        }
        return terminals
    }

    private func terminal(pinName: String, shapes: [ShapeRecord]) -> RawLayoutTerminal? {
        guard let layer = shapes.first?.layer,
              let rect = mergeRects(shapes.map({ LayoutGeometryAnalysis.boundingBox(for: $0.geometry) })) else {
            return nil
        }
        return RawLayoutTerminal(pinName: pinName, layer: layer, geometry: .rect(rect))
    }

    private func mergeRects(_ rects: [LayoutRect]) -> LayoutRect? {
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() {
            result = result.union(rect)
        }
        return result
    }

    private func rangesOverlap(_ lhsMin: Double, _ lhsMax: Double, _ rhsMin: Double, _ rhsMax: Double) -> Bool {
        lhsMin <= rhsMax && rhsMin <= lhsMax
    }

    private func positiveIntersection(_ lhs: LayoutRect, _ rhs: LayoutRect) -> LayoutRect? {
        let minX = max(lhs.minX, rhs.minX)
        let maxX = min(lhs.maxX, rhs.maxX)
        let minY = max(lhs.minY, rhs.minY)
        let maxY = min(lhs.maxY, rhs.maxY)
        guard maxX > minX, maxY > minY else { return nil }
        return LayoutRect(
            origin: LayoutPoint(x: minX, y: minY),
            size: LayoutSize(width: maxX - minX, height: maxY - minY)
        )
    }

    private func transformed(_ geometry: LayoutGeometry, by transforms: [LayoutTransform]) -> LayoutGeometry {
        var result = geometry
        for transform in transforms {
            result = result.transformed(by: transform)
        }
        return result
    }

    private func transformed(_ point: LayoutPoint, by transforms: [LayoutTransform]) -> LayoutPoint {
        var result = point
        for transform in transforms {
            result = transform.apply(to: result)
        }
        return result
    }
}

private struct IndexedUnionFind: Sendable {
    private var parents: [Int]

    init(count: Int) {
        self.parents = Array(0..<count)
    }

    mutating func find(_ value: Int) -> Int {
        let parent = parents[value]
        if parent == value {
            return value
        }
        let root = find(parent)
        parents[value] = root
        return root
    }

    mutating func union(_ lhs: Int, _ rhs: Int) {
        let leftRoot = find(lhs)
        let rightRoot = find(rhs)
        if leftRoot != rightRoot {
            parents[rightRoot] = leftRoot
        }
    }
}
