import Foundation
import LayoutCore
import LayoutTech

/// Translates a generic-tech layout document (`LayoutTechDatabase.sampleProcess()`
/// layer names: ACTIVE/POLY/CONTACT/M1/M2/NWELL/NIMP/PIMP) into the Sky130 layer
/// stack so the real Magic/Netgen deck can verify agent-generated artifacts.
///
/// This is a STRUCTURAL mapping, not a layer rename:
/// - ACTIVE classifies into `diff` (device diffusion) or `tap` (well/substrate
///   tie) from its implant cover and nwell containment
/// - each CONTACT cut becomes the Sky130 local-interconnect stack
///   licon1 -> li1 -> mcon, with `npc` and a poly landing pad over poly
///   contacts, and tap/implant growth where Sky130 requires deeper enclosure
///   than the generic process drew
/// - via entities are re-pointed at the Sky130 via definition, so their cut
///   geometry re-derives at Sky130 size on export
///
/// Correctness is NOT claimed by this type: the translated artifact is meant
/// to be judged by Magic DRC + Netgen LVS, which remain the authority. The
/// translator's own contract is completeness — every input element is either
/// translated to a layer the Sky130 tech defines or the translation throws;
/// nothing is dropped or passed through silently.
public struct Sky130TechTranslator {

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
                return "Layer '\(layer)' in cell '\(cell)' has no Sky130 translation."
            case .unsupportedViaDefinition(let id, let cell):
                return "Via definition '\(id)' in cell '\(cell)' has no Sky130 translation."
            case .nonRectangularContact(let cell):
                return "A non-rectangular CONTACT cut in cell '\(cell)' cannot be restacked."
            case .nonRectangularTap(let cell):
                return "A non-rectangular tap diffusion in cell '\(cell)' cannot be grown for Sky130 enclosure."
            case .unclassifiableActive(let cell):
                return "An ACTIVE shape in cell '\(cell)' has no covering implant; it cannot classify as diff or tap."
            case .contactOutsideDeviceGeometry(let cell):
                return "A CONTACT cut in cell '\(cell)' lies on neither POLY nor ACTIVE."
            case .targetDefinitionMissing(let id):
                return "The Sky130 target tech is missing the '\(id)' definition."
            }
        }
    }

    /// Generic layer name -> Sky130 layer name, for layers that map 1:1.
    /// ACTIVE and CONTACT are handled structurally and are absent here.
    private static let layerMap: [String: String] = [
        "NWELL": "nwell",
        "POLY": "poly",
        "NIMP": "nsdm",
        "PIMP": "psdm",
        "M1": "met1",
        "M2": "met2",
    ]

    private static let viaDefinitionMap: [String: String] = [
        "VIA1": "via",
    ]

    // Sky130 rule constants the tech database does not carry.
    /// npc enclosure of a poly licon1 (Sky130 npc.1).
    private static let npcEnclosureOfLicon = 0.10
    /// Poly enclosure of licon1 on a landing pad (Sky130 licon.8a).
    private static let polyPadEnclosureOfLicon = 0.08
    /// Tap enclosure of licon1 on one pair of opposite sides (Sky130 licon.7).
    private static let tapEnclosureOfLiconPair = 0.12
    /// nsdm/psdm enclosure of diff/tap (Sky130 nsdm.2/psdm.2).
    private static let implantEnclosureOfTap = 0.125

    private let target = Sky130LayoutTech.tech()

    public init() {}

    public func translate(_ document: LayoutDocument) throws -> Output {
        guard let liconDefinition = target.viaDefinition(for: "licon1") else {
            throw TranslationError.targetDefinitionMissing("licon1")
        }
        guard let mconDefinition = target.viaDefinition(for: "mcon") else {
            throw TranslationError.targetDefinitionMissing("mcon")
        }
        var translated = document
        translated.cells = try document.cells.map {
            try translate(cell: $0, licon: liconDefinition, mcon: mconDefinition)
        }
        return Output(document: translated, tech: target)
    }

    // MARK: - Cell translation

    private func translate(
        cell: LayoutCell,
        licon: LayoutViaDefinition,
        mcon: LayoutViaDefinition
    ) throws -> LayoutCell {
        let context = ClassificationContext(cell: cell)
        var result = cell

        // Pass 1: contact cuts -> licon1/li1/mcon stacks; collect the licon
        // rectangles per tap so pass 2 can grow tap enclosures around them.
        // Active-hosted contacts in the same column (one diffusion, one net)
        // share a single merged li1 strip: per-cut pads at the generic cut
        // pitch land 0.14um apart, violating Sky130 li.3 (0.17um spacing).
        var shapes: [LayoutShape] = []
        var tapLicons: [UUID: [LayoutRect]] = [:]
        var liColumns: [ColumnKey: LiColumn] = [:]
        for shape in cell.shapes where shape.layer.name == "CONTACT" {
            guard let cut = Self.rectangle(from: shape.geometry) else {
                throw TranslationError.nonRectangularContact(cell: cell.name)
            }
            let stack = try contactStack(
                cut: cut,
                netID: shape.netID,
                context: context,
                cellName: cell.name,
                licon: licon,
                mcon: mcon
            )
            shapes.append(contentsOf: stack.shapes)
            if let activeID = stack.hostActiveShapeID, stack.hostIsTap {
                tapLicons[activeID, default: []].append(stack.liconRect)
            }
            if let activeID = stack.hostActiveShapeID {
                // A tap is one electrical node, so all its licons share one
                // strip; device diffusion hosts distinct source/drain nets,
                // so those merge per contact column only.
                let key = ColumnKey(
                    hostID: activeID,
                    xKey: stack.hostIsTap ? nil : Self.nanometerKey(stack.liconRect.minX)
                )
                liColumns[key, default: LiColumn()].add(licon: stack.liconRect, netID: shape.netID)
            }
        }
        let liEnclosure = licon.enclosure.top
        for column in liColumns.values {
            guard let extent = column.extent else { continue }
            shapes.append(LayoutShape(
                layer: Sky130LayoutTech.layer("li1"),
                netID: column.netID,
                geometry: .rect(extent.expanded(by: liEnclosure, liEnclosure))
            ))
        }

        // Pass 2: every non-contact shape translates by classification (ACTIVE)
        // or by the layer map; anything else is unsupported and throws.
        for var shape in cell.shapes where shape.layer.name != "CONTACT" {
            switch shape.layer.name {
            case "ACTIVE":
                shapes.append(try translateActive(
                    shape,
                    context: context,
                    cellName: cell.name,
                    licons: tapLicons[shape.id] ?? []
                ))
            default:
                guard let mapped = Self.layerMap[shape.layer.name] else {
                    throw TranslationError.unsupportedLayer(layer: shape.layer.name, cell: cell.name)
                }
                shape.layer = Sky130LayoutTech.layer(mapped)
                shapes.append(shape)
            }
        }

        // Implants covering a grown tap must keep the Sky130 enclosure; widen
        // them to the extent the grown tap now requires.
        shapes = growImplants(in: shapes, requirements: implantRequirements(cell: cell, tapLicons: tapLicons))

        result.shapes = shapes
        result.vias = try cell.vias.map { via in
            guard let mapped = Self.viaDefinitionMap[via.viaDefinitionID] else {
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
        guard let mapped = Self.layerMap[layer.name] else {
            throw TranslationError.unsupportedLayer(layer: layer.name, cell: cell)
        }
        return Sky130LayoutTech.layer(mapped)
    }

    // MARK: - Contact restacking

    private struct ContactStack {
        let shapes: [LayoutShape]
        let liconRect: LayoutRect
        /// The id of the ACTIVE shape hosting this contact; nil for poly
        /// contacts, whose li1 pad is emitted with the stack itself.
        let hostActiveShapeID: UUID?
        /// Whether the hosting active classifies as a tap (well/substrate tie).
        let hostIsTap: Bool
    }

    /// Groups active-hosted contacts into one li1 strip per contact column
    /// (`xKey` is nil for taps, which merge whole-host).
    private struct ColumnKey: Hashable {
        let hostID: UUID
        let xKey: Int?
    }

    private struct LiColumn {
        private(set) var extent: LayoutRect?
        private(set) var netID: UUID?

        mutating func add(licon: LayoutRect, netID: UUID?) {
            extent = extent.map { $0.union(licon) } ?? licon
            if self.netID == nil { self.netID = netID }
        }
    }

    private func contactStack(
        cut: LayoutRect,
        netID: UUID?,
        context: ClassificationContext,
        cellName: String,
        licon: LayoutViaDefinition,
        mcon: LayoutViaDefinition
    ) throws -> ContactStack {
        let center = cut.center
        let liconRect = Self.centered(at: center, size: licon.cutSize)
        let mconRect = Self.centered(at: center, size: mcon.cutSize)

        var shapes: [LayoutShape] = [
            LayoutShape(layer: Sky130LayoutTech.layer("licon1"), netID: netID, geometry: .rect(liconRect)),
            LayoutShape(layer: Sky130LayoutTech.layer("mcon"), netID: netID, geometry: .rect(mconRect)),
        ]

        if context.poly.contains(where: { $0.contains(center) }) {
            // A gate-input contact: Sky130 needs npc over the licon and a poly
            // pad wide enough for the licon.8a enclosure (the generic gate
            // stripe can be narrower than the cut). Gate contacts are single,
            // so their li1 pad is emitted here rather than column-merged.
            let liEnclosure = licon.enclosure.top
            let liRect = liconRect.expanded(by: liEnclosure, liEnclosure)
            let npcRect = liconRect.expanded(by: Self.npcEnclosureOfLicon, Self.npcEnclosureOfLicon)
            let padRect = liconRect.expanded(by: Self.polyPadEnclosureOfLicon, Self.polyPadEnclosureOfLicon)
            shapes.append(LayoutShape(layer: Sky130LayoutTech.layer("li1"), netID: netID, geometry: .rect(liRect)))
            shapes.append(LayoutShape(layer: Sky130LayoutTech.layer("npc"), geometry: .rect(npcRect)))
            shapes.append(LayoutShape(layer: Sky130LayoutTech.layer("poly"), netID: netID, geometry: .rect(padRect)))
            return ContactStack(shapes: shapes, liconRect: liconRect, hostActiveShapeID: nil, hostIsTap: false)
        }

        guard let host = context.actives.first(where: { $0.box.contains(center) }) else {
            throw TranslationError.contactOutsideDeviceGeometry(cell: cellName)
        }
        let isTap = try classify(activeCenter: host.box.center, context: context, cellName: cellName) == .tap
        return ContactStack(shapes: shapes, liconRect: liconRect, hostActiveShapeID: host.id, hostIsTap: isTap)
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

        init(cell: LayoutCell) {
            func boxes(_ name: String) -> [LayoutRect] {
                cell.shapes
                    .filter { $0.layer.name == name }
                    .map { LayoutGeometryAnalysis.boundingBox(for: $0.geometry) }
            }
            actives = cell.shapes
                .filter { $0.layer.name == "ACTIVE" }
                .map { Active(id: $0.id, box: LayoutGeometryAnalysis.boundingBox(for: $0.geometry)) }
            poly = boxes("POLY")
            nimp = boxes("NIMP")
            pimp = boxes("PIMP")
            nwell = boxes("NWELL")
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
        licons: [LayoutRect]
    ) throws -> LayoutShape {
        let box = LayoutGeometryAnalysis.boundingBox(for: shape.geometry)
        var translated = shape
        switch try classify(activeCenter: box.center, context: context, cellName: cellName) {
        case .diff:
            translated.layer = Sky130LayoutTech.layer("diff")
        case .tap:
            translated.layer = Sky130LayoutTech.layer("tap")
            guard let rect = Self.rectangle(from: shape.geometry) else {
                throw TranslationError.nonRectangularTap(cell: cellName)
            }
            translated.geometry = .rect(Self.grownTap(rect, licons: licons))
        }
        return translated
    }

    /// Sky130 licon.7 wants the tap to enclose its licon by 0.12 on one pair
    /// of opposite sides; the generic process drew a tighter tap. Widen the
    /// tap horizontally — never shrink — until every licon has that margin.
    private static func grownTap(_ tap: LayoutRect, licons: [LayoutRect]) -> LayoutRect {
        guard !licons.isEmpty else { return tap }
        let requiredMinX = licons.map(\.minX).min().map { $0 - tapEnclosureOfLiconPair } ?? tap.minX
        let requiredMaxX = licons.map(\.maxX).max().map { $0 + tapEnclosureOfLiconPair } ?? tap.maxX
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
    /// by the Sky130 implant-of-tap margin. Derived from geometry, never from
    /// assumed generic enclosures.
    private func implantRequirements(
        cell: LayoutCell,
        tapLicons: [UUID: [LayoutRect]]
    ) -> [UUID: (minX: Double, maxX: Double)] {
        var requirements: [UUID: (minX: Double, maxX: Double)] = [:]
        for shape in cell.shapes where shape.layer.name == "ACTIVE" {
            guard let licons = tapLicons[shape.id], !licons.isEmpty,
                  let rect = Self.rectangle(from: shape.geometry) else { continue }
            let grown = Self.grownTap(rect, licons: licons)
            guard grown != rect else { continue }
            // The covering implant is the one containing the tap center; the
            // device implant never contains it because implants only enclose
            // their own diffusion.
            let center = rect.center
            for implant in cell.shapes where implant.layer.name == "NIMP" || implant.layer.name == "PIMP" {
                let box = LayoutGeometryAnalysis.boundingBox(for: implant.geometry)
                if box.contains(center) {
                    requirements[implant.id] = (
                        minX: grown.minX - Self.implantEnclosureOfTap,
                        maxX: grown.maxX + Self.implantEnclosureOfTap
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
