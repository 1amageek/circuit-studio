import Foundation
import CircuitStudioCore
import LayoutCore
import LayoutTech
import LayoutAutoGen
import LayoutVerify

/// Placement algorithm strategy.
public enum PlacementStrategy: Sendable {
    /// Greedy row-based placement (fast, lower quality).
    case greedy
    /// Simulated annealing optimization (slower, higher quality).
    case optimized
}

/// Routing algorithm strategy.
public enum RoutingStrategy: Sendable {
    /// Simple Manhattan MST routing.
    case simple
    /// Steiner tree routing with congestion-aware rip-up/reroute.
    case steiner
}

/// Output of the auto-layout generation pipeline.
public struct AutoLayoutOutput: Sendable {
    public let document: LayoutDocument
    public let tech: LayoutTechDatabase
    public let designUnit: DesignUnit
    public let drcResult: LayoutDRCResult
    public let unroutedNets: [String]
    public let skippedComponents: [String]
    public let metrics: LayoutQualityMetrics
}

/// Orchestrates the full auto-layout pipeline: net extraction → cell generation → placement → routing → DRC.
@MainActor
public final class AutoLayoutService {
    private let defaultTech: LayoutTechDatabase
    private var cellCache: DeviceCellCache
    private let mosfetGen: MOSFETCellGenerator
    private let resistorGen: ResistorCellGenerator
    private let capacitorGen: CapacitorCellGenerator

    public init(tech: LayoutTechDatabase = .sampleProcess()) {
        self.defaultTech = tech
        self.cellCache = DeviceCellCache()
        self.mosfetGen = MOSFETCellGenerator()
        self.resistorGen = ResistorCellGenerator()
        self.capacitorGen = CapacitorCellGenerator()
    }

    public func generate(
        from document: SchematicDocument,
        catalog: DeviceCatalog,
        tech overrideTech: LayoutTechDatabase? = nil,
        placementStrategy: PlacementStrategy = .greedy,
        routingStrategy: RoutingStrategy = .simple,
        constraints: [LayoutConstraint] = []
    ) throws -> AutoLayoutOutput {
        let tech = ensureContactDefinitions(overrideTech ?? defaultTech)

        // 1. Extract nets
        let nets = NetExtractor().extract(from: document)

        // 2. Generate device cells and placement instances
        var cells: [UUID: LayoutCell] = [:]
        var instances: [PlacementInstance] = []
        var componentToCellID: [UUID: UUID] = [:]
        var skipped: [String] = []

        for component in document.components {
            guard let kind = catalog.device(for: component.deviceKindID) else { continue }
            // Skip reference devices (ground, VDD, terminals)
            guard kind.category != .special else { continue }
            // Skip sources/controlled sources (no physical layout)
            guard kind.category != .source, kind.category != .controlled else {
                skipped.append(component.name)
                continue
            }

            let generator = resolveGenerator(for: kind)
            guard let gen = generator else {
                skipped.append(component.name)
                continue
            }

            let deviceKindForGen = classifyDeviceKindID(kind)
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
                deviceType: classifyDeviceType(kind),
                name: component.name
            ))
        }

        // 3. Build placement nets
        let placementNets = buildPlacementNets(nets: nets, instanceIDs: Set(instances.map(\.id)))

        // 4. Place
        let placement: PlacementResult
        switch placementStrategy {
        case .greedy:
            placement = RowBasedPlacementEngine().place(
                instances: instances,
                nets: placementNets,
                tech: tech
            )
        case .optimized:
            let saEngine = SAPlacementEngine(
                configuration: .init(initialTemperature: 1000, coolingRate: 0.97, minTemperature: 0.1),
                constraints: constraints
            )
            placement = saEngine.place(
                instances: instances,
                nets: placementNets,
                tech: tech
            )
        }

        // 5. Build routing nets with absolute pin positions
        let routingNets = buildRoutingNets(
            nets: nets,
            instances: instances,
            placement: placement,
            cells: cells,
            componentToCellID: componentToCellID
        )

        // 6. Route
        let routing: RoutingResult
        switch routingStrategy {
        case .simple:
            routing = SimpleRoutingEngine().route(
                nets: routingNets,
                placements: placement.placements,
                cells: cells,
                obstructions: placement.powerRails,
                tech: tech
            )
        case .steiner:
            routing = SteinerRoutingEngine().route(
                nets: routingNets,
                placements: placement.placements,
                cells: cells,
                obstructions: placement.powerRails,
                tech: tech
            )
        }

        // 7. Assemble LayoutDocument
        let layoutDoc = assembleDocument(
            name: "AutoLayout",
            cells: cells,
            instances: instances,
            placement: placement,
            routing: routing,
            componentToCellID: componentToCellID
        )

        // 8. DRC
        let drcResult = LayoutDRCService().run(document: layoutDoc, tech: tech)

        // 9. Build DesignUnit
        let designUnit = buildDesignUnit(
            document: document,
            layoutDoc: layoutDoc,
            componentToCellID: componentToCellID,
            nets: nets,
            routingNets: routingNets
        )

        // 10. Evaluate quality metrics
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

        return AutoLayoutOutput(
            document: layoutDoc,
            tech: tech,
            designUnit: designUnit,
            drcResult: drcResult,
            unroutedNets: routing.unroutedNets,
            skippedComponents: skipped,
            metrics: metrics
        )
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

    // MARK: - Generator Resolution

    private func resolveGenerator(for kind: DeviceKind) -> (any DeviceCellGenerator)? {
        if let modelType = kind.modelType {
            switch modelType {
            case "NMOS", "PMOS":
                return mosfetGen
            default:
                break
            }
        }

        switch kind.spicePrefix {
        case "R":
            return resistorGen
        case "C":
            return capacitorGen
        case "M":
            return mosfetGen
        default:
            return nil
        }
    }

    private func classifyDeviceKindID(_ kind: DeviceKind) -> String {
        if let modelType = kind.modelType {
            switch modelType {
            case "NMOS": return "nmos"
            case "PMOS": return "pmos"
            default: break
            }
        }
        switch kind.spicePrefix {
        case "R": return "resistor"
        case "C": return "capacitor"
        case "M":
            return kind.modelType == "PMOS" ? "pmos" : "nmos"
        default:
            return kind.id
        }
    }

    private func classifyDeviceType(_ kind: DeviceKind) -> DeviceType {
        if let modelType = kind.modelType {
            switch modelType {
            case "NMOS": return .nmos
            case "PMOS": return .pmos
            default: break
            }
        }
        return .passive
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
                    layer: m1ID
                )
            }

            guard pins.count >= 2 else { return nil }

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
        componentToCellID: [UUID: UUID]
    ) -> LayoutDocument {
        // Create top cell with instances and routing shapes
        var topShapes: [LayoutShape] = placement.powerRails
        var topVias: [LayoutVia] = []
        var topInstances: [LayoutInstance] = []

        // Add device cell instances
        for inst in instances {
            guard let cellID = componentToCellID[inst.id],
                  let transform = placement.placements[inst.id] else { continue }
            topInstances.append(LayoutInstance(
                cellID: cellID,
                name: inst.name,
                transform: transform
            ))
        }

        // Add routing shapes and vias
        for route in routing.routes {
            topShapes.append(contentsOf: route.shapes)
            topVias.append(contentsOf: route.vias)
        }

        let topCell = LayoutCell(
            name: "TOP",
            shapes: topShapes,
            vias: topVias,
            instances: topInstances
        )

        var allCells = Array(cells.values)
        allCells.append(topCell)

        return LayoutDocument(
            name: name,
            cells: allCells,
            topCellID: topCell.id
        )
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
