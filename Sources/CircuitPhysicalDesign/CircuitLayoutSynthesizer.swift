import Foundation
import CircuitStudioCore
import LayoutCore
import LayoutTech
import LayoutAutoGen
import LayoutEngine
import LayoutVerify

/// Output of the circuit-to-layout synthesis pipeline.
public struct CircuitLayoutSynthesisOutput: Sendable {
    public let document: LayoutDocument
    public let tech: LayoutTechDatabase
    public let designUnit: DesignUnit
    public let drcResult: LayoutDRCResult
    public let unroutedNets: [String]
    public let skippedComponents: [String]
    public let metrics: LayoutQualityMetrics
    /// Rip-up-and-reroute rounds the DRC repair loop executed.
    public let repairIterations: Int
    /// Antenna jumpers inserted by the post-route mitigation pass.
    public let antennaJumpersInserted: Int
    /// Gates the antenna mitigation pass could not protect, with reasons.
    /// Their violations remain in `drcResult` — nothing is dropped.
    public let antennaMitigationFailures: [String]
}

/// Orchestrates circuit-to-layout synthesis: net extraction → cell generation → placement → routing → DRC.
public final class CircuitLayoutSynthesizer {
    private let defaultTech: LayoutTechDatabase
    private let layoutEngineCatalog: any LayoutEngineCataloging
    private var cellCache: DeviceCellCache

    public init(
        tech: LayoutTechDatabase = .sampleProcess(),
        layoutEngineCatalog: any LayoutEngineCataloging = CircuitPhysicalDesignDefaults.layoutEngineCatalog()
    ) {
        self.defaultTech = tech
        self.layoutEngineCatalog = layoutEngineCatalog
        self.cellCache = DeviceCellCache()
    }

    public func generate(
        from document: SchematicDocument,
        catalog: DeviceCatalog,
        tech overrideTech: LayoutTechDatabase? = nil,
        placementStrategy: PlacementEngineSelection = .greedy,
        routingStrategy: RoutingEngineSelection = .simple,
        constraints: [LayoutConstraint] = []
    ) throws -> CircuitLayoutSynthesisOutput {
        let tech = ensureContactDefinitions(overrideTech ?? defaultTech)

        // 1. Extract nets
        let nets = NetExtractor().extract(from: document)

        // 2. Generate device cells and placement instances
        var cells: [UUID: LayoutCell] = [:]
        var instances: [PlacementInstance] = []
        var componentToCellID: [UUID: UUID] = [:]
        var skipped: [String] = []

        // Project-cell instances need hierarchical layout generation, which
        // does not exist yet — fail before producing a partial layout.
        let cellInstances = document.components.filter { $0.cellName != nil }
        guard cellInstances.isEmpty else {
            throw CircuitLayoutSynthesisError.hierarchicalCellsUnsupported(
                instanceNames: cellInstances.map(\.name)
            )
        }
        let duplicateNames = duplicatedComponentNames(in: document.components)
        guard duplicateNames.isEmpty else {
            throw CircuitLayoutSynthesisError.duplicateComponentNames(duplicateNames)
        }

        for component in document.components {
            guard let kind = catalog.device(for: component.deviceKindID) else {
                throw CircuitLayoutSynthesisError.unknownDeviceKind(
                    instanceName: component.name,
                    deviceKindID: component.deviceKindID
                )
            }
            // Skip reference devices (ground, VDD) and boundary ports — no geometry
            guard kind.category != .special, kind.category != .port else { continue }
            // Skip sources/controlled sources (no physical layout)
            guard kind.category != .source, kind.category != .controlled else {
                skipped.append(component.name)
                continue
            }

            let deviceKindForGen = PhysicalDeviceMapper.canonicalDeviceKindID(kind)
            let generator = layoutEngineCatalog.deviceCellGenerator(canonicalDeviceKindID: deviceKindForGen)
            guard let gen = generator else {
                throw CircuitLayoutSynthesisError.unsupportedLayoutDevice(
                    instanceName: component.name,
                    deviceKindID: component.deviceKindID
                )
            }

            let layoutParams = convertParametersToMicrometers(
                component.parameters, kind: kind
            )
            let cell = try cellCache.cellFor(
                deviceKindID: deviceKindForGen,
                instanceName: component.name,
                parameters: layoutParams,
                generator: gen,
                tech: tech
            )
            cells[cell.id] = cell
            componentToCellID[component.id] = cell.id

            instances.append(PlacementInstance(
                id: component.id,
                cell: cell,
                deviceType: PhysicalDeviceMapper.deviceType(kind),
                name: component.name
            ))
        }
        guard !instances.isEmpty else {
            throw CircuitLayoutSynthesisError.noPlaceableComponents
        }

        // 3. Build placement nets
        let placementNets = buildPlacementNets(nets: nets, instanceIDs: Set(instances.map(\.id)))

        // 4. Place
        let placementEngine = try layoutEngineCatalog.makePlacementEngine(
            for: placementStrategy,
            constraints: constraints
        )
        let placement = try placementEngine.place(
            instances: instances,
            nets: placementNets,
            tech: tech
        )

        // 5. Build routing nets with absolute pin positions
        let routingNets = buildRoutingNets(
            nets: nets,
            instances: instances,
            placement: placement,
            cells: cells,
            componentToCellID: componentToCellID
        )

        // 6.-8. Route, assemble, and verify in a DRC-driven repair loop:
        // violations attributed to routed nets trigger rip-up and reroute
        // against the kept routes; whatever survives the budget is carried
        // into the reported DRC result instead of being dropped.
        let engine = try layoutEngineCatalog.makeRoutingEngine(for: routingStrategy)
        let verifier = try layoutEngineCatalog.makePostRouteVerifier(tech: tech)
        let outcome = try DRCDrivenRoutingLoop().run(
            nets: routingNets,
            placements: placement.placements,
            cells: cells,
            obstructions: placement.powerRails,
            tech: tech,
            engine: engine,
            verifier: verifier,
            assemble: { routing in
                self.assembleDocument(
                    name: "CircuitLayoutSynthesis",
                    cells: cells,
                    instances: instances,
                    placement: placement,
                    routing: routing,
                    routingNets: routingNets,
                    componentToCellID: componentToCellID
                )
            }
        )
        let routing = outcome.routing
        var layoutDoc = outcome.document

        // Same-net sliver gaps cannot be rerouted away — the connectivity
        // that put both shapes there is legitimate — so merge them by
        // bridging before the final DRC judges the result.
        SameNetSliverBridger().bridge(document: &layoutDoc, tech: tech)

        // The loop's verifier only carries errors; rerun full DRC so the
        // reported result keeps warnings as well.
        var drcResult = LayoutDRCService().run(document: layoutDoc, tech: tech)

        // 9. Antenna mitigation: the repair loop excludes antenna violations
        // because rip-up reproduces the same topology; instead, insert layer
        // jumpers next to the affected gates and rerun DRC. The rerun is the
        // single source of truth for whether the mitigation worked.
        let mitigation = try mitigateAntennaViolations(
            document: &layoutDoc,
            drcResult: &drcResult,
            tech: tech
        )

        // 10. Build DesignUnit
        let designUnit = buildDesignUnit(
            document: document,
            layoutDoc: layoutDoc,
            componentToCellID: componentToCellID,
            nets: nets,
            routingNets: routingNets
        )

        // 11. Evaluate quality metrics
        let evaluator = LayoutQualityEvaluator()
        var metrics = evaluator.evaluate(
            document: layoutDoc,
            tech: tech,
            routingResult: routing,
            placementNets: placementNets,
            placements: placement.placements,
            instances: instances,
            constraints: constraints
        )
        let drcViolations = drcResult.violations.map {
            DRCViolationInfo(kind: $0.kind.rawValue, message: $0.message)
        }
        evaluator.injectDRC(violations: drcViolations, into: &metrics)

        return CircuitLayoutSynthesisOutput(
            document: layoutDoc,
            tech: tech,
            designUnit: designUnit,
            drcResult: drcResult,
            unroutedNets: routing.unroutedNets,
            skippedComponents: skipped,
            metrics: metrics,
            repairIterations: outcome.repairIterations,
            antennaJumpersInserted: mitigation.insertedJumpers,
            antennaMitigationFailures: mitigation.failures
        )
    }

    // MARK: - Antenna Mitigation

    private struct AntennaMitigationSummary {
        var insertedJumpers: Int
        var failures: [String]
    }

    /// Repairs antenna violations reported by `drcResult` by inserting layer
    /// jumpers near the affected gates, rerunning DRC after each round. Stops
    /// after `maxRounds`, when no antenna violations remain, or when a round
    /// makes no progress. Failures reflect the final state: a gate that a
    /// later round repaired is not reported, and when the final DRC result is
    /// antenna-clean the failure list is empty. Reported failures always have
    /// their violations still present in the final `drcResult`.
    private func mitigateAntennaViolations(
        document: inout LayoutDocument,
        drcResult: inout LayoutDRCResult,
        tech: LayoutTechDatabase,
        maxRounds: Int = 3
    ) throws -> AntennaMitigationSummary {
        var insertedJumpers = 0
        var failures: [String] = []
        let inserter = AntennaJumperInserter()

        for _ in 0..<maxRounds {
            let antennaViolations = actionableAntennaViolations(in: drcResult)
            guard !antennaViolations.isEmpty,
                  let topCellID = document.topCellID else { break }

            // Merge per violating layer: PAR and CAR findings on the same
            // layer share gates, so deduplication avoids double jumpers.
            var layerOrder: [LayoutLayerID] = []
            var shapeIDsByLayer: [LayoutLayerID: [UUID]] = [:]
            var gatesByLayer: [LayoutLayerID: [AntennaJumperGate]] = [:]
            for violation in antennaViolations {
                guard let layer = violation.layer else { continue }
                if shapeIDsByLayer[layer] == nil { layerOrder.append(layer) }
                shapeIDsByLayer[layer, default: []].append(contentsOf: violation.shapeIDs)
                gatesByLayer[layer, default: []].append(
                    contentsOf: gateTerminals(forPinIDs: violation.pinIDs, in: document)
                )
            }
            let requests = layerOrder.compactMap { layer -> AntennaJumperRequest? in
                let gates = orderedDeduplicated(gatesByLayer[layer] ?? [])
                guard !gates.isEmpty else { return nil }
                return AntennaJumperRequest(
                    layer: layer,
                    shapeIDs: orderedDeduplicated(shapeIDsByLayer[layer] ?? []),
                    gates: gates
                )
            }
            guard !requests.isEmpty else { break }

            let result = try inserter.insert(
                requests: requests,
                into: &document,
                cellID: topCellID,
                tech: tech
            )
            // Overwrite, not accumulate: a later round can repair a gate
            // that an earlier round failed on (the first jumper changes the
            // component, so the next violation lists different candidate
            // wires). Only the last round describes the final document.
            failures = result.failures.map(\.description)
            guard result.insertedJumpers > 0 else { break }
            insertedJumpers += result.insertedJumpers
            drcResult = LayoutDRCService().run(document: document, tech: tech)
        }

        // A failure is only meaningful while its violation survives; when
        // the final DRC is antenna-clean the transient failures are stale.
        if actionableAntennaViolations(in: drcResult).isEmpty {
            failures = []
        }

        return AntennaMitigationSummary(
            insertedJumpers: insertedJumpers,
            failures: orderedDeduplicated(failures)
        )
    }

    /// Antenna violations a jumper pass can act on. Configuration violations
    /// (antenna.config.*) carry no shape IDs; they describe tech-database
    /// gaps a jumper cannot fix.
    private func actionableAntennaViolations(in result: LayoutDRCResult) -> [LayoutViolation] {
        result.violations.filter {
            $0.kind == .antenna && !$0.shapeIDs.isEmpty && !$0.pinIDs.isEmpty
        }
    }

    /// Maps violation pin IDs back to absolute gate terminals. Device pins
    /// live one instancing level below TOP (the only structure this service
    /// assembles), so a single transform application matches the positions
    /// the DRC flatten reported; pin sizes are not rotated, matching the
    /// flatten's own behavior. Cell deduplication means one pin ID can map
    /// to several instance positions; all of them are returned.
    private func gateTerminals(
        forPinIDs pinIDs: [UUID],
        in document: LayoutDocument
    ) -> [AntennaJumperGate] {
        guard let topCellID = document.topCellID,
              let topCell = document.cell(withID: topCellID) else { return [] }
        let pinIDSet = Set(pinIDs)
        var gates: [AntennaJumperGate] = []
        for pin in topCell.pins where pinIDSet.contains(pin.id) {
            gates.append(AntennaJumperGate(position: pin.position, size: pin.size))
        }
        for instance in topCell.instances {
            guard let cell = document.cell(withID: instance.cellID) else { continue }
            for pin in cell.pins where pinIDSet.contains(pin.id) {
                gates.append(AntennaJumperGate(
                    position: instance.transform.apply(to: pin.position),
                    size: pin.size
                ))
            }
        }
        return gates
    }

    private func orderedDeduplicated<Element: Hashable>(_ values: [Element]) -> [Element] {
        var seen = Set<Element>()
        return values.filter { seen.insert($0).inserted }
    }

    // MARK: - Contact Definition Synthesis

    /// Ensures CONT_ACTIVE and CONT_POLY contact definitions exist.
    /// When importing from TechIR/LEF, these may be absent. Synthesizes them from
    /// available layer rules and enclosure rules to prevent MOSFETCellGenerator failures.
    private func ensureContactDefinitions(_ tech: LayoutTechDatabase) -> LayoutTechDatabase {
        var result = tech

        let contID = LayoutLayerID(name: "CONTACT", purpose: "cut")
        let activeID = LayoutLayerID(name: "ACTIVE", purpose: "drawing")
        let polyID = LayoutLayerID(name: "POLY", purpose: "drawing")
        let m1ID = LayoutLayerID(name: "M1", purpose: "drawing")

        let contRules = tech.ruleSet(for: contID)
        let contSize = contRules?.minWidth ?? 0.22
        let contSpacing = contRules?.minSpacing ?? 0.25

        // Derive enclosure from existing rules or use defaults
        let activeEnc = tech.enclosureRule(outer: activeID, inner: contID)?.minEnclosure ?? 0.06
        let m1Enc = tech.enclosureRule(outer: m1ID, inner: contID)?.minEnclosure ?? 0.06
        let polyEnc = tech.enclosureRule(outer: polyID, inner: contID)?.minEnclosure ?? 0.08

        if tech.contactDefinition(for: "CONT_ACTIVE") == nil {
            result.contacts.append(LayoutContactDefinition(
                id: "CONT_ACTIVE",
                cutLayer: contID,
                bottomLayer: activeID,
                topLayer: m1ID,
                cutSize: LayoutSize(width: contSize, height: contSize),
                enclosure: LayoutViaEnclosure(top: m1Enc, bottom: activeEnc),
                cutSpacing: contSpacing
            ))
        }

        if tech.contactDefinition(for: "CONT_POLY") == nil {
            result.contacts.append(LayoutContactDefinition(
                id: "CONT_POLY",
                cutLayer: contID,
                bottomLayer: polyID,
                topLayer: m1ID,
                cutSize: LayoutSize(width: contSize, height: contSize),
                enclosure: LayoutViaEnclosure(top: m1Enc, bottom: polyEnc),
                cutSpacing: contSpacing
            ))
        }

        return result
    }

    private func duplicatedComponentNames(in components: [PlacedComponent]) -> [String] {
        var counts: [String: Int] = [:]
        for component in components {
            counts[component.name, default: 0] += 1
        }
        return counts
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
    }

    // MARK: - Parameter Unit Conversion

    /// Converts schematic parameters (SI units) to layout units (micrometers).
    ///
    /// MOSFET w/l: meters → µm (×1e6)
    /// Resistor r: ohms → ohms (no conversion)
    /// Capacitor c: farads → farads (no conversion)
    private func convertParametersToMicrometers(
        _ params: [String: Double],
        kind: DeviceKind
    ) -> [String: Double] {
        var result = params
        if let modelType = kind.modelType,
           (modelType == "NMOS" || modelType == "PMOS") || kind.spicePrefix == "M" {
            if let w = result["w"] {
                result["w"] = w * 1e6
            }
            if let l = result["l"] {
                result["l"] = l * 1e6
            }
        }
        return result
    }

    // MARK: - Net Building

    private func buildPlacementNets(
        nets: [ExtractedNet],
        instanceIDs: Set<UUID>
    ) -> [PlacementNet] {
        nets.compactMap { net in
            let connections = net.connections
                .filter { instanceIDs.contains($0.componentID) }
                .map { (instanceID: $0.componentID, pinName: $0.portID) }
            guard connections.count >= 2 else { return nil }
            return PlacementNet(name: net.name, pinConnections: connections)
        }
    }

    private func buildRoutingNets(
        nets: [ExtractedNet],
        instances: [PlacementInstance],
        placement: PlacementResult,
        cells: [UUID: LayoutCell],
        componentToCellID: [UUID: UUID]
    ) -> [RoutingNet] {
        let m1ID = LayoutLayerID(name: "M1", purpose: "drawing")
        let instanceIDs = Set(instances.map(\.id))

        return nets.compactMap { net in
            let pins: [RoutingPin] = net.connections.compactMap { conn in
                guard instanceIDs.contains(conn.componentID) else { return nil }
                guard let cellID = componentToCellID[conn.componentID],
                      let cell = cells[cellID],
                      let transform = placement.placements[conn.componentID] else { return nil }

                // Find matching pin in cell
                let pin = cell.pins.first { $0.name == conn.portID }
                    ?? cell.pins.first { matchPinName($0.name, to: conn.portID) }

                guard let cellPin = pin else { return nil }

                let absPos = transform.apply(to: cellPin.position)
                return RoutingPin(
                    instanceID: conn.componentID,
                    pinName: conn.portID,
                    absolutePosition: absPos,
                    layer: m1ID,
                    size: cellPin.size
                )
            }

            guard !pins.isEmpty else { return nil }

            let isPower = Self.isPowerNetName(net.name)

            return RoutingNet(
                id: UUID(),
                name: net.name,
                pins: pins,
                isPower: isPower
            )
        }
    }

    /// Checks if a net name represents a power/ground net.
    private static func isPowerNetName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower == "vdd" || lower == "vcc"
            || lower == "vss" || lower == "gnd"
            || lower == "0"
    }

    private func matchPinName(_ cellPinName: String, to portID: String) -> Bool {
        // Exact match for each device type's port → pin mapping.
        // Passive devices use pos/neg; MOSFETs use drain/gate/source/bulk.
        // These are 1:1 mappings; no ambiguous multi-pin fallback.
        let mappings: [String: String] = [
            "pos": "pos",
            "neg": "neg",
            "drain": "drain",
            "gate": "gate",
            "source": "source",
            "bulk": "bulk",
        ]
        if let expected = mappings[portID] {
            return cellPinName == expected
        }
        return cellPinName.lowercased() == portID.lowercased()
    }

    // MARK: - Document Assembly

    private func assembleDocument(
        name: String,
        cells: [UUID: LayoutCell],
        instances: [PlacementInstance],
        placement: PlacementResult,
        routing: RoutingResult,
        routingNets: [RoutingNet],
        componentToCellID: [UUID: UUID]
    ) -> LayoutDocument {
        // Create top cell with instances and routing shapes
        var topShapes: [LayoutShape] = assignPowerRailNets(
            placement.powerRails,
            routingNets: routingNets
        )
        var topVias: [LayoutVia] = []
        var topInstances: [LayoutInstance] = []
        var topNets: [LayoutNet] = []
        var topPins: [LayoutPin] = []
        var addedNetIDs = Set<UUID>()
        let netNamesByID = Dictionary(uniqueKeysWithValues: routingNets.map { ($0.id, $0.name) })

        // Add device cell instances
        for inst in instances {
            guard let cellID = componentToCellID[inst.id],
                  let transform = placement.placements[inst.id] else { continue }
            topInstances.append(LayoutInstance(
                cellID: cellID,
                name: inst.name,
                transform: transform,
                terminalNetIDs: terminalNetIDs(for: inst.id, routingNets: routingNets)
            ))
        }

        // Add routing shapes and vias
        for route in routing.routes {
            if let netName = netNamesByID[route.netID] {
                appendTopNet(id: route.netID, name: netName, nets: &topNets, addedNetIDs: &addedNetIDs)
            }

            topShapes.append(contentsOf: route.shapes.map { shape in
                var routedShape = shape
                routedShape.netID = route.netID
                return routedShape
            })
            topVias.append(contentsOf: route.vias.map { via in
                var routedVia = via
                routedVia.netID = route.netID
                return routedVia
            })
        }

        for net in routingNets {
            appendTopNet(id: net.id, name: net.name, nets: &topNets, addedNetIDs: &addedNetIDs)
            guard net.pins.count == 1, let pin = net.pins.first else { continue }
            topPins.append(LayoutPin(
                name: net.name,
                position: pin.absolutePosition,
                size: LayoutSize(width: 0.4, height: 0.4),
                layer: pin.layer,
                netID: net.id,
                role: Self.isPowerNetName(net.name) ? .power : .signal
            ))
        }

        let topCell = LayoutCell(
            name: "TOP",
            shapes: topShapes,
            vias: topVias,
            pins: topPins,
            instances: topInstances,
            nets: topNets
        )

        var allCells = Array(cells.values)
        allCells.append(topCell)

        return LayoutDocument(
            name: name,
            cells: allCells,
            topCellID: topCell.id
        )
    }

    private func terminalNetIDs(for instanceID: UUID, routingNets: [RoutingNet]) -> [String: UUID] {
        var terminalNetIDs: [String: UUID] = [:]
        for net in routingNets {
            for pin in net.pins where pin.instanceID == instanceID {
                terminalNetIDs[pin.pinName] = net.id
            }
        }
        return terminalNetIDs
    }

    private func appendTopNet(
        id: UUID,
        name: String,
        nets: inout [LayoutNet],
        addedNetIDs: inout Set<UUID>
    ) {
        guard !addedNetIDs.contains(id) else { return }
        nets.append(LayoutNet(id: id, name: name))
        addedNetIDs.insert(id)
    }

    private func assignPowerRailNets(
        _ powerRails: [LayoutShape],
        routingNets: [RoutingNet]
    ) -> [LayoutShape] {
        let groundNetID = routingNets.first {
            let name = $0.name.lowercased()
            return name == "0" || name == "vss" || name == "gnd"
        }?.id
        let supplyNetID = routingNets.first {
            let name = $0.name.lowercased()
            return name == "vdd" || name == "vcc"
        }?.id

        let indexedRails = powerRails.enumerated().sorted {
            railCenterY($0.element) < railCenterY($1.element)
        }
        var netIDsByIndex: [Int: UUID] = [:]
        if let first = indexedRails.first, let groundNetID {
            netIDsByIndex[first.offset] = groundNetID
        }
        if let last = indexedRails.last, let supplyNetID {
            netIDsByIndex[last.offset] = supplyNetID
        }

        return powerRails.enumerated().map { index, shape in
            var nettedShape = shape
            if let netID = netIDsByIndex[index] {
                nettedShape.netID = netID
            } else {
                nettedShape.properties[LayoutOwnershipPolicy.defaultExemptionProperty] = "non-net"
            }
            return nettedShape
        }
    }

    private func railCenterY(_ shape: LayoutShape) -> Double {
        switch shape.geometry {
        case .rect(let rect):
            return rect.origin.y + rect.size.height / 2
        case .polygon(let polygon):
            guard let first = polygon.points.first else { return 0 }
            var minY = first.y
            var maxY = first.y
            for point in polygon.points.dropFirst() {
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            return (minY + maxY) / 2
        case .path(let path):
            guard let first = path.points.first else { return 0 }
            var minY = first.y
            var maxY = first.y
            for point in path.points.dropFirst() {
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            return (minY + maxY) / 2
        }
    }

    // MARK: - DesignUnit

    private func buildDesignUnit(
        document: SchematicDocument,
        layoutDoc: LayoutDocument,
        componentToCellID: [UUID: UUID],
        nets: [ExtractedNet],
        routingNets: [RoutingNet]
    ) -> DesignUnit {
        // Component → Instance mapping
        var compToInst: [UUID: UUID] = [:]
        if let topCell = layoutDoc.topCellID.flatMap({ layoutDoc.cell(withID: $0) }) {
            for inst in topCell.instances {
                // Match by name — find the component with the same name
                if let comp = document.components.first(where: { $0.name == inst.name }) {
                    compToInst[comp.id] = inst.id
                }
            }
        }

        // Net name → LayoutNet.id mapping
        var netMapping: [String: UUID] = [:]
        for routingNet in routingNets {
            netMapping[routingNet.name] = routingNet.id
        }

        // DeviceKindID → Cell ID mapping
        var deviceKindToCell: [String: UUID] = [:]
        for (compID, cellID) in componentToCellID {
            if let comp = document.components.first(where: { $0.id == compID }) {
                deviceKindToCell[comp.deviceKindID] = cellID
            }
        }

        // Compute schematic hash
        let hash = DesignUnit.schematicHash(for: document)

        return DesignUnit(
            componentToInstance: compToInst,
            netNameToLayoutNet: netMapping,
            deviceKindToCell: deviceKindToCell,
            schematicHash: hash
        )
    }

}
