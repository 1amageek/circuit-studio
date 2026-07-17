import PEXEngine

public extension ParasiticElement {
    init(
        id: String,
        kind: ElementKind,
        nodeA: String,
        nodeB: String?,
        value: Double,
        source: ElementSource = .userDefined
    ) {
        self.init(
            id: id,
            kind: kind,
            nodeA: NodeRef(netName: NetName(nodeA), nodeName: NodeName(nodeA)),
            nodeB: nodeB.map { NodeRef(netName: NetName($0), nodeName: NodeName($0)) },
            value: value,
            source: source
        )
    }
}

public extension ParasiticIR {
    init(
        version: String = ParasiticIR.currentVersion,
        cornerID: String,
        units: ParasiticUnits = .canonical,
        elements: [ParasiticElement],
        metadata: [String: String] = [:]
    ) {
        self.init(
            version: version,
            cornerID: PEXCornerID(cornerID),
            units: units,
            nets: Self.makeNets(from: elements, units: units),
            elements: elements,
            metadata: metadata
        )
    }

    private static func makeNets(
        from elements: [ParasiticElement],
        units: ParasiticUnits
    ) -> [ParasiticNet] {
        let references = Set(elements.flatMap { element in
            [element.nodeA] + (element.nodeB.map { [$0] } ?? [])
        })
        return Dictionary(grouping: references, by: \.netName)
            .map { netName, refs in
                let groundCapacitance = elements
                    .filter { $0.kind == .capacitor && $0.nodeA.netName == netName && $0.nodeB == nil }
                    .reduce(0) { $0 + capacitanceInFarads($1.value, unit: units.capacitance) }
                let couplingCapacitance = elements
                    .filter {
                        $0.kind == .coupling
                            && ($0.nodeA.netName == netName || $0.nodeB?.netName == netName)
                    }
                    .reduce(0) { $0 + capacitanceInFarads($1.value, unit: units.capacitance) }
                let resistance = elements
                    .filter {
                        $0.kind == .resistor
                            && ($0.nodeA.netName == netName || $0.nodeB?.netName == netName)
                    }
                    .reduce(0) { $0 + resistanceInOhms($1.value, unit: units.resistance) }
                return ParasiticNet(
                    name: netName,
                    nodes: refs
                        .map { ParasiticNode(name: $0.nodeName, kind: .internal, instancePath: nil, coordinate: nil) }
                        .sorted { $0.name.value < $1.name.value },
                    totalGroundCapF: groundCapacitance,
                    totalCouplingCapF: couplingCapacitance,
                    totalResistanceOhm: resistance
                )
            }
            .sorted { $0.name.value < $1.name.value }
    }

    private static func resistanceInOhms(
        _ value: Double,
        unit: ParasiticUnits.ResistanceUnit
    ) -> Double {
        switch unit {
        case .ohm: value
        case .kiloOhm: value * 1e3
        }
    }

    private static func capacitanceInFarads(
        _ value: Double,
        unit: ParasiticUnits.CapacitanceUnit
    ) -> Double {
        switch unit {
        case .farad: value
        case .picoFarad: value * 1e-12
        case .femtoFarad: value * 1e-15
        }
    }
}
