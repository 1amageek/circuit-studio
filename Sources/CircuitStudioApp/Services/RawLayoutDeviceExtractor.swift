import LayoutCore
import LayoutTech

struct RawLayoutDeviceExtractor: Sendable {
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
