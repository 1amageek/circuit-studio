import Foundation
import LayoutCore
import LayoutTech

/// Translates generic-tech layout documents into a profile-declared target
/// technology.
///
/// This is a STRUCTURAL mapping, not a layer rename:
/// - active regions classify into device diffusion or well/substrate taps from
///   profile-declared implant cover and well containment layers
/// - each contact cut becomes the profile-declared local-interconnect stack,
///   including gate-contact masks, landing pads, and tap/implant growth
/// - via entities are re-pointed at the profile-declared target via definition
///
/// Correctness is NOT claimed by this type: the translated artifact is meant to
/// be judged by signoff DRC/LVS, which remain the authority. The translator's
/// own contract is completeness: every input element is either translated to a
/// layer the target tech defines or the translation throws; nothing is dropped
/// or passed through silently. Process policy lives in profile artifacts, not
/// in this Swift implementation.
public struct LayoutTechnologyTranslator {
    public struct Output: Sendable {
        public let document: LayoutDocument
        public let tech: LayoutTechDatabase
    }

    public enum TranslationError: Error, LocalizedError, Equatable {
        case unsupportedLayer(layer: String, cell: String)
        case unsupportedViaDefinition(id: String, cell: String)
        case nonRectangularContact(cell: String)
        case nonRectangularTap(cell: String)
        case unclassifiableActive(cell: String)
        case contactOutsideDeviceGeometry(cell: String)
        case targetDefinitionMissing(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedLayer(let layer, let cell):
                return "Layer '\(layer)' in cell '\(cell)' has no translation profile mapping."
            case .unsupportedViaDefinition(let id, let cell):
                return "Via definition '\(id)' in cell '\(cell)' has no translation profile mapping."
            case .nonRectangularContact(let cell):
                return "A non-rectangular contact cut in cell '\(cell)' cannot be restacked."
            case .nonRectangularTap(let cell):
                return "A non-rectangular tap diffusion in cell '\(cell)' cannot be grown for target enclosure."
            case .unclassifiableActive(let cell):
                return "An active shape in cell '\(cell)' has no covering implant; it cannot classify as diffusion or tap."
            case .contactOutsideDeviceGeometry(let cell):
                return "A contact cut in cell '\(cell)' lies on neither gate conductor nor active geometry."
            case .targetDefinitionMissing(let id):
                return "The target tech is missing the '\(id)' definition."
            }
        }
    }

    public let profile: LayoutTechnologyTranslationProfile
    private let target: LayoutTechDatabase

    public init(profile: LayoutTechnologyTranslationProfile, target: LayoutTechDatabase) {
        self.profile = profile
        self.target = target
    }

    public static func bundled(resourceName: String) throws -> LayoutTechnologyTranslator {
        let profile = try LayoutTechnologyTranslationProfile.bundled(resourceName: resourceName)
        let target = try LayoutTechnologyResource.bundled(resourceName: profile.targetTechnologyResourceName)
        return LayoutTechnologyTranslator(profile: profile, target: target)
    }

    public func translate(_ document: LayoutDocument) throws -> Output {
        let policy = profile.contactRestackPolicy
        guard let activeContactDefinition = target.viaDefinition(for: policy.activeContactViaDefinitionID) else {
            throw TranslationError.targetDefinitionMissing(policy.activeContactViaDefinitionID)
        }
        guard let metalContactDefinition = target.viaDefinition(for: policy.metalContactViaDefinitionID) else {
            throw TranslationError.targetDefinitionMissing(policy.metalContactViaDefinitionID)
        }
        var translated = document
        translated.cells = try document.cells.map {
            try translate(
                cell: $0,
                activeContact: activeContactDefinition,
                metalContact: metalContactDefinition
            )
        }
        return Output(document: translated, tech: target)
    }

    // MARK: - Cell translation

    private func translate(
        cell: LayoutCell,
        activeContact: LayoutViaDefinition,
        metalContact: LayoutViaDefinition
    ) throws -> LayoutCell {
        let sourceLayers = profile.sourceLayers
        let context = ClassificationContext(cell: cell, sourceLayers: sourceLayers)
        var result = cell

        // Pass 1: contact cuts -> profile-declared local stack; collect
        // contact rectangles per tap so pass 2 can grow tap enclosures.
        // Active-hosted contacts in the same column (one diffusion, one net)
        // share a single merged local-interconnect strip when per-cut pads
        // would violate target local-interconnect spacing.
        var shapes: [LayoutShape] = []
        var tapContactCuts: [UUID: [LayoutRect]] = [:]
        var localInterconnectColumns: [ColumnKey: LocalInterconnectColumn] = [:]
        for shape in cell.shapes where shape.layer.name == sourceLayers.contact {
            guard let cut = Self.rectangle(from: shape.geometry) else {
                throw TranslationError.nonRectangularContact(cell: cell.name)
            }
            let stack = try contactStack(
                cut: cut,
                netID: shape.netID,
                context: context,
                cellName: cell.name,
                activeContact: activeContact,
                metalContact: metalContact
            )
            shapes.append(contentsOf: stack.shapes)
            if let activeID = stack.hostActiveShapeID, stack.hostIsTap {
                tapContactCuts[activeID, default: []].append(stack.activeContactRect)
            }
            if let activeID = stack.hostActiveShapeID {
                // A tap is one electrical node, so all its contact cuts share
                // one strip; device diffusion hosts distinct source/drain
                // nets, so those merge per contact column only.
                let key = ColumnKey(
                    hostID: activeID,
                    xKey: stack.hostIsTap ? nil : Self.nanometerKey(stack.activeContactRect.minX)
                )
                localInterconnectColumns[key, default: LocalInterconnectColumn()].add(
                    contactCut: stack.activeContactRect,
                    netID: shape.netID
                )
            }
        }
        let localInterconnectEnclosure = activeContact.enclosure.top
        for column in localInterconnectColumns.values {
            guard let extent = column.extent else { continue }
            shapes.append(LayoutShape(
                layer: targetLayer(profile.targetLayers.localInterconnect),
                netID: column.netID,
                geometry: .rect(extent.expanded(by: localInterconnectEnclosure, localInterconnectEnclosure))
            ))
        }

        // Pass 2: every non-contact shape translates by active classification
        // or by the layer map; anything else is unsupported and throws.
        for var shape in cell.shapes where shape.layer.name != sourceLayers.contact {
            if shape.layer.name == sourceLayers.active {
                shapes.append(try translateActive(
                    shape,
                    context: context,
                    cellName: cell.name,
                    contactCuts: tapContactCuts[shape.id] ?? []
                ))
            } else {
                guard let mapped = profile.layerMap[shape.layer.name] else {
                    throw TranslationError.unsupportedLayer(layer: shape.layer.name, cell: cell.name)
                }
                shape.layer = targetLayer(mapped)
                shapes.append(shape)
            }
        }

        // Implants covering a grown tap must keep the profile-declared
        // enclosure; widen them to the extent the grown tap now requires.
        shapes = growImplants(in: shapes, requirements: implantRequirements(cell: cell, tapContactCuts: tapContactCuts))

        result.shapes = shapes
        result.vias = try cell.vias.map { via in
            guard let mapped = profile.viaDefinitionMap[via.viaDefinitionID] else {
                throw TranslationError.unsupportedViaDefinition(id: via.viaDefinitionID, cell: cell.name)
            }
            var translatedVia = via
            translatedVia.viaDefinitionID = mapped
            return translatedVia
        }
        result.labels = try cell.labels.map { label in
            var translatedLabel = label
            translatedLabel.layer = try mappedReferenceLayer(label.layer, cell: cell.name)
            return translatedLabel
        }
        result.pins = try cell.pins.map { pin in
            var translatedPin = pin
            translatedPin.layer = try mappedReferenceLayer(pin.layer, cell: cell.name)
            return translatedPin
        }
        return result
    }

    /// Labels and pins reference layers by name only; they may sit on any
    /// 1:1-mapped layer (metals in practice).
    private func mappedReferenceLayer(_ layer: LayoutLayerID, cell: String) throws -> LayoutLayerID {
        guard let mapped = profile.layerMap[layer.name] else {
            throw TranslationError.unsupportedLayer(layer: layer.name, cell: cell)
        }
        return targetLayer(mapped)
    }

    private func targetLayer(_ reference: LayoutTechnologyTranslationProfile.LayerReference) -> LayoutLayerID {
        LayoutLayerID(name: reference.name, purpose: reference.purpose)
    }

    // MARK: - Contact restacking

    private struct ContactStack {
        let shapes: [LayoutShape]
        let activeContactRect: LayoutRect
        /// The id of the active shape hosting this contact; nil for gate
        /// contacts, whose local-interconnect pad is emitted with the stack.
        let hostActiveShapeID: UUID?
        /// Whether the hosting active classifies as a tap (well/substrate tie).
        let hostIsTap: Bool
    }

    /// Groups active-hosted contacts into one local-interconnect strip per
    /// contact column (`xKey` is nil for taps, which merge whole-host).
    private struct ColumnKey: Hashable {
        let hostID: UUID
        let xKey: Int?
    }

    private struct LocalInterconnectColumn {
        private(set) var extent: LayoutRect?
        private(set) var netID: UUID?

        mutating func add(contactCut: LayoutRect, netID: UUID?) {
            extent = extent.map { $0.union(contactCut) } ?? contactCut
            if self.netID == nil { self.netID = netID }
        }
    }

    private func contactStack(
        cut: LayoutRect,
        netID: UUID?,
        context: ClassificationContext,
        cellName: String,
        activeContact: LayoutViaDefinition,
        metalContact: LayoutViaDefinition
    ) throws -> ContactStack {
        let center = cut.center
        let activeContactRect = Self.centered(at: center, size: activeContact.cutSize)
        let metalContactRect = Self.centered(at: center, size: metalContact.cutSize)
        let targetLayers = profile.targetLayers
        let policy = profile.contactRestackPolicy

        var shapes: [LayoutShape] = [
            LayoutShape(layer: targetLayer(targetLayers.contactCut), netID: netID, geometry: .rect(activeContactRect)),
            LayoutShape(layer: targetLayer(targetLayers.metalContactCut), netID: netID, geometry: .rect(metalContactRect)),
        ]

        if context.poly.contains(where: { $0.contains(center) }) {
            // A gate-input contact needs the profile-declared cut mask and
            // conductor pad. Gate contacts are single, so their local
            // interconnect pad is emitted here rather than column-merged.
            let localInterconnectEnclosure = activeContact.enclosure.top
            let localInterconnectRect = activeContactRect.expanded(
                by: localInterconnectEnclosure,
                localInterconnectEnclosure
            )
            let gateCutMaskRect = activeContactRect.expanded(
                by: policy.gateCutMaskEnclosure,
                policy.gateCutMaskEnclosure
            )
            let gateConductorPadRect = activeContactRect.expanded(
                by: policy.gatePadEnclosure,
                policy.gatePadEnclosure
            )
            shapes.append(LayoutShape(
                layer: targetLayer(targetLayers.localInterconnect),
                netID: netID,
                geometry: .rect(localInterconnectRect)
            ))
            shapes.append(LayoutShape(
                layer: targetLayer(targetLayers.gateCutMask),
                geometry: .rect(gateCutMaskRect)
            ))
            shapes.append(LayoutShape(
                layer: targetLayer(targetLayers.gateConductor),
                netID: netID,
                geometry: .rect(gateConductorPadRect)
            ))
            return ContactStack(
                shapes: shapes,
                activeContactRect: activeContactRect,
                hostActiveShapeID: nil,
                hostIsTap: false
            )
        }

        guard let host = context.actives.first(where: { $0.box.contains(center) }) else {
            throw TranslationError.contactOutsideDeviceGeometry(cell: cellName)
        }
        let isTap = try classify(activeCenter: host.box.center, context: context, cellName: cellName) == .tap
        return ContactStack(
            shapes: shapes,
            activeContactRect: activeContactRect,
            hostActiveShapeID: host.id,
            hostIsTap: isTap
        )
    }

    // MARK: - Active classification

    private enum ActiveKind {
        case diff
        case tap
    }

    private struct ClassificationContext {
        struct Active {
            let id: UUID
            let box: LayoutRect
        }

        let actives: [Active]
        let poly: [LayoutRect]
        let nimp: [LayoutRect]
        let pimp: [LayoutRect]
        let nwell: [LayoutRect]

        init(cell: LayoutCell, sourceLayers: LayoutTechnologyTranslationProfile.SourceLayers) {
            func boxes(_ name: String) -> [LayoutRect] {
                cell.shapes
                    .filter { $0.layer.name == name }
                    .map { LayoutGeometryAnalysis.boundingBox(for: $0.geometry) }
            }
            actives = cell.shapes
                .filter { $0.layer.name == sourceLayers.active }
                .map { Active(id: $0.id, box: LayoutGeometryAnalysis.boundingBox(for: $0.geometry)) }
            poly = boxes(sourceLayers.poly)
            nimp = boxes(sourceLayers.nImplant)
            pimp = boxes(sourceLayers.pImplant)
            nwell = boxes(sourceLayers.nWell)
        }
    }

    private func classify(
        activeCenter: LayoutPoint,
        context: ClassificationContext,
        cellName: String
    ) throws -> ActiveKind {
        let inWell = context.nwell.contains { $0.contains(activeCenter) }
        if context.nimp.contains(where: { $0.contains(activeCenter) }) {
            return inWell ? .tap : .diff
        }
        if context.pimp.contains(where: { $0.contains(activeCenter) }) {
            return inWell ? .diff : .tap
        }
        throw TranslationError.unclassifiableActive(cell: cellName)
    }

    private func translateActive(
        _ shape: LayoutShape,
        context: ClassificationContext,
        cellName: String,
        contactCuts: [LayoutRect]
    ) throws -> LayoutShape {
        let box = LayoutGeometryAnalysis.boundingBox(for: shape.geometry)
        var translated = shape
        switch try classify(activeCenter: box.center, context: context, cellName: cellName) {
        case .diff:
            translated.layer = targetLayer(profile.targetLayers.diffusion)
        case .tap:
            translated.layer = targetLayer(profile.targetLayers.tap)
            guard let rect = Self.rectangle(from: shape.geometry) else {
                throw TranslationError.nonRectangularTap(cell: cellName)
            }
            translated.geometry = .rect(grownTap(rect, contactCuts: contactCuts))
        }
        return translated
    }

    /// Widen a tap horizontally, never shrink it, until every hosted contact
    /// cut has the profile-declared margin on one pair of opposite sides.
    private func grownTap(_ tap: LayoutRect, contactCuts: [LayoutRect]) -> LayoutRect {
        guard !contactCuts.isEmpty else { return tap }
        let margin = profile.contactRestackPolicy.tapContactHorizontalEnclosure
        let requiredMinX = contactCuts.map(\.minX).min().map { $0 - margin } ?? tap.minX
        let requiredMaxX = contactCuts.map(\.maxX).max().map { $0 + margin } ?? tap.maxX
        let minX = min(tap.minX, requiredMinX)
        let maxX = max(tap.maxX, requiredMaxX)
        return LayoutRect(
            origin: LayoutPoint(x: minX, y: tap.minY),
            size: LayoutSize(width: maxX - minX, height: tap.size.height)
        )
    }

    // MARK: - Implant growth over grown taps

    /// Required horizontal extent (minX, maxX) keyed by the ORIGINAL implant
    /// shape id: the implant covering a grown tap must enclose the grown tap
    /// by the profile-declared implant-of-tap margin. Derived from geometry,
    /// never from assumed generic enclosures.
    private func implantRequirements(
        cell: LayoutCell,
        tapContactCuts: [UUID: [LayoutRect]]
    ) -> [UUID: (minX: Double, maxX: Double)] {
        var requirements: [UUID: (minX: Double, maxX: Double)] = [:]
        let sourceLayers = profile.sourceLayers
        let implantLayers = Set([sourceLayers.nImplant, sourceLayers.pImplant])
        let implantEnclosure = profile.contactRestackPolicy.tapImplantEnclosure
        for shape in cell.shapes where shape.layer.name == sourceLayers.active {
            guard let contactCuts = tapContactCuts[shape.id], !contactCuts.isEmpty,
                  let rect = Self.rectangle(from: shape.geometry) else { continue }
            let grown = grownTap(rect, contactCuts: contactCuts)
            guard grown != rect else { continue }
            // The covering implant is the one containing the tap center; the
            // device implant never contains it because implants only enclose
            // their own diffusion.
            let center = rect.center
            for implant in cell.shapes where implantLayers.contains(implant.layer.name) {
                let box = LayoutGeometryAnalysis.boundingBox(for: implant.geometry)
                if box.contains(center) {
                    requirements[implant.id] = (
                        minX: grown.minX - implantEnclosure,
                        maxX: grown.maxX + implantEnclosure
                    )
                }
            }
        }
        return requirements
    }

    private func growImplants(
        in shapes: [LayoutShape],
        requirements: [UUID: (minX: Double, maxX: Double)]
    ) -> [LayoutShape] {
        guard !requirements.isEmpty else { return shapes }
        return shapes.map { shape in
            guard let required = requirements[shape.id],
                  let rect = Self.rectangle(from: shape.geometry) else { return shape }
            let minX = min(rect.minX, required.minX)
            let maxX = max(rect.maxX, required.maxX)
            var grown = shape
            grown.geometry = .rect(LayoutRect(
                origin: LayoutPoint(x: minX, y: rect.minY),
                size: LayoutSize(width: maxX - minX, height: rect.size.height)
            ))
            return grown
        }
    }

    // MARK: - Geometry helpers

    /// The axis-aligned rectangle a geometry denotes, when it denotes one:
    /// a `.rect` directly, or a `.polygon` whose vertices are exactly the
    /// four corners of an axis-aligned rectangle. GDS boundaries reimport
    /// as polygons, so translated artifacts that round-tripped through GDS
    /// carry rectangular polygons where the editor drew rects.
    private static func rectangle(from geometry: LayoutGeometry) -> LayoutRect? {
        switch geometry {
        case .rect(let rect):
            return rect
        case .polygon(let polygon):
            var points = polygon.points
            if points.count > 1, points.first == points.last {
                points.removeLast()
            }
            guard points.count == 4, Set(points).count == 4 else { return nil }
            let xs = Set(points.map(\.x))
            let ys = Set(points.map(\.y))
            guard xs.count == 2, ys.count == 2,
                  let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return nil }
            return LayoutRect(
                origin: LayoutPoint(x: minX, y: minY),
                size: LayoutSize(width: maxX - minX, height: maxY - minY)
            )
        case .path:
            return nil
        }
    }

    /// Coordinates quantize to integer nanometers for grouping: GDS stores
    /// integer database units, so cuts in one column share the same key.
    private static func nanometerKey(_ coordinate: Double) -> Int {
        Int((coordinate * 1000).rounded())
    }

    private static func centered(at point: LayoutPoint, size: LayoutSize) -> LayoutRect {
        LayoutRect(
            origin: LayoutPoint(x: point.x - size.width / 2, y: point.y - size.height / 2),
            size: size
        )
    }
}
