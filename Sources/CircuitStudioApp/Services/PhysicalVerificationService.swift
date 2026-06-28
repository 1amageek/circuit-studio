import Foundation
import CircuitStudioCore
import LayoutCore
import LayoutTech
import LayoutVerify

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

