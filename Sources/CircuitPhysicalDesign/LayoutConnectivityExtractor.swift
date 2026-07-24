import Foundation
import LayoutCore
import LayoutTech

struct LayoutConnectivityExtractor: Sendable {
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
