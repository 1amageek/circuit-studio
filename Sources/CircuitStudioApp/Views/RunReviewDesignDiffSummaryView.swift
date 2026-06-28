import SwiftUI

struct RunReviewDesignDiffSummaryView: View {
    let summary: RunReviewDesignDiffSummary

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("actor")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(summary.actor)
                        .font(.caption2.monospaced())
                    Spacer()
                    Text("\(summary.changeCount) change(s)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                designDiffBucketRow(title: "Domains", buckets: summary.domains)
                designDiffBucketRow(title: "Operations", buckets: summary.operations)
                designDiffSnapshotRow(title: "Base snapshot", snapshot: summary.baseSnapshot)
                designDiffSnapshotRow(title: "Proposed snapshot", snapshot: summary.proposedSnapshot)
                if !summary.canvases.isEmpty {
                    designDiffCanvasList(summary.canvases)
                }
                ForEach(summary.changes, id: \.changeID) { change in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            planningStatusBadge(change.operation)
                            Text(change.domain)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 76, alignment: .leading)
                            Text(change.summary)
                                .font(.caption)
                            Spacer()
                            if change.artifactCount > 0 {
                                Text("\(change.artifactCount) artifact(s)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(change.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if let visualFocus = change.visualFocus {
                            designDiffVisualFocusPane(visualFocus)
                        }
                        if let pathContext = change.pathContext {
                            designDiffPathContextRow(pathContext)
                        }
                        if let fromPath = change.fromPath {
                            Text("from \(fromPath)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if change.beforePreview != nil || change.afterPreview != nil {
                            HStack(alignment: .top, spacing: 8) {
                                designDiffValuePreview("Before", value: change.beforePreview)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                designDiffValuePreview("After", value: change.afterPreview)
                            }
                        }
                        if !change.valueChanges.isEmpty {
                            designDiffValueChangeList(change.valueChanges)
                        }
                        ForEach(change.artifacts, id: \.path) { artifact in
                            designDiffArtifactRow(artifact)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(.top, 3)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.orange)
                Text(summary.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                planningStatusBadge(summary.reviewState)
            }
        }
    }

    @ViewBuilder
    private func designDiffBucketRow(
        title: String,
        buckets: [RunReviewDesignDiffBucket]
    ) -> some View {
        if !buckets.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .leading)
                Text(buckets.map { "\($0.label) \($0.count)" }.joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func designDiffSnapshotRow(
        title: String,
        snapshot: RunReviewDesignDiffArtifactSummary?
    ) -> some View {
        if let snapshot {
            HStack(alignment: .top, spacing: 6) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)
                designDiffArtifactRow(snapshot)
            }
        }
    }

    private func designDiffCanvasList(
        _ canvases: [RunReviewDesignDiffCanvasSummary]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Visual diff")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(canvases, id: \.canvasID) { canvas in
                designDiffCanvasPane(canvas)
            }
        }
    }

    private func designDiffCanvasPane(
        _ canvas: RunReviewDesignDiffCanvasSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: designDiffPathContextIcon(canvas.scope))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(canvas.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(canvas.nodeCount) node(s)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text("\(canvas.changedFieldCount) field(s)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let viewport = canvas.viewport,
               let rendering = canvas.rendering {
                designDiffCanvasNativeRenderingMap(
                    canvas,
                    viewport: viewport,
                    rendering: rendering
                )
            } else if let viewport = canvas.viewport {
                designDiffCanvasViewportMap(canvas, viewport: viewport)
            }
            designDiffCanvasBody(canvas)
                .frame(minHeight: 74)
        }
        .padding(6)
        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    private func designDiffCanvasBody(
        _ canvas: RunReviewDesignDiffCanvasSummary
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.secondary.opacity(0.04))
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(canvas.nodes.enumerated()), id: \.element.nodeID) { index, node in
                        if index > 0 {
                            Rectangle()
                                .fill(.secondary.opacity(0.28))
                                .frame(width: 24, height: 1)
                        }
                        designDiffCanvasNode(node)
                    }
                }
                .padding(8)
            }
        }
    }

    private func designDiffCanvasViewportMap(
        _ canvas: RunReviewDesignDiffCanvasSummary,
        viewport: RunReviewDesignDiffCanvasViewportSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.background.opacity(0.72))
                    ForEach(canvas.nodes, id: \.nodeID) { node in
                        if let geometry = node.geometry {
                            if let beforeFrame = geometry.beforeFrame {
                                designDiffCanvasGeometryRect(
                                    beforeFrame,
                                    bounds: viewport.bounds,
                                    canvasSize: proxy.size
                                )
                                .stroke(.secondary.opacity(0.52), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            }
                            if let afterFrame = geometry.afterFrame {
                                designDiffCanvasGeometryRect(
                                    afterFrame,
                                    bounds: viewport.bounds,
                                    canvasSize: proxy.size
                                )
                                .fill(planningStatusColor(node.emphasis).opacity(0.16))
                                designDiffCanvasGeometryRect(
                                    afterFrame,
                                    bounds: viewport.bounds,
                                    canvasSize: proxy.size
                                )
                                .stroke(planningStatusColor(node.emphasis).opacity(0.8), lineWidth: 1)
                            }
                        }
                    }
                }
            }
            .frame(height: 76)
            HStack(spacing: 8) {
                Text(designDiffCanvasFrameText(viewport.bounds))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !viewport.layerIDs.isEmpty {
                    Text(viewport.layerIDs.joined(separator: ", "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(viewport.geometryNodeCount) geom")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func designDiffCanvasNativeRenderingMap(
        _ canvas: RunReviewDesignDiffCanvasSummary,
        viewport: RunReviewDesignDiffCanvasViewportSummary,
        rendering: RunReviewDesignDiffCanvasRenderingSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(rendering.coordinateSpace)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("before \(rendering.beforePrimitiveCount)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text("after \(rendering.afterPrimitiveCount)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.background.opacity(0.72))
                    if let beforeBounds = viewport.beforeBounds {
                        designDiffCanvasGeometryRect(
                            beforeBounds,
                            bounds: viewport.bounds,
                            canvasSize: proxy.size
                        )
                        .stroke(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    }
                    if let afterBounds = viewport.afterBounds {
                        designDiffCanvasGeometryRect(
                            afterBounds,
                            bounds: viewport.bounds,
                            canvasSize: proxy.size
                        )
                        .stroke(.primary.opacity(0.12), lineWidth: 1)
                    }
                    ForEach(rendering.primitives, id: \.primitiveID) { primitive in
                        if let beforeFrame = primitive.beforeFrame {
                            designDiffCanvasGeometryRect(
                                beforeFrame,
                                bounds: viewport.bounds,
                                canvasSize: proxy.size
                            )
                            .stroke(.secondary.opacity(0.58), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        }
                        if let afterFrame = primitive.afterFrame {
                            designDiffCanvasGeometryRect(
                                afterFrame,
                                bounds: viewport.bounds,
                                canvasSize: proxy.size
                            )
                            .fill(planningStatusColor(primitive.emphasis).opacity(0.18))
                            designDiffCanvasGeometryRect(
                                afterFrame,
                                bounds: viewport.bounds,
                                canvasSize: proxy.size
                            )
                            .stroke(planningStatusColor(primitive.emphasis).opacity(0.84), lineWidth: 1.25)
                        }
                    }
                    ForEach(rendering.primitives, id: \.primitiveID) { primitive in
                        if let selectionFrame = primitive.selectionFrame {
                            let labelPoint = designDiffCanvasPrimitiveLabelPoint(
                                selectionFrame,
                                bounds: viewport.bounds,
                                canvasSize: proxy.size
                            )
                            Text(primitive.label)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.background.opacity(0.84), in: RoundedRectangle(cornerRadius: 3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(planningStatusColor(primitive.emphasis).opacity(0.55), lineWidth: 0.75)
                                )
                                .position(labelPoint)
                        }
                    }
                }
            }
            .frame(height: designDiffCanvasNativeHeight(aspectRatio: rendering.aspectRatio))
            HStack(spacing: 8) {
                Text(designDiffCanvasFrameText(viewport.bounds))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(rendering.overlayPrimitiveCount) overlay")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if !rendering.layers.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(rendering.layers, id: \.layerID) { layer in
                            Text(designDiffCanvasLayerText(layer))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            if !rendering.primitives.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(rendering.primitives, id: \.primitiveID) { primitive in
                            Text(designDiffCanvasPrimitiveText(primitive))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(planningStatusColor(primitive.emphasis).opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func designDiffCanvasNode(
        _ node: RunReviewDesignDiffCanvasNodeSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: designDiffVisualFocusIcon(node.kind))
                    .font(.caption)
                    .foregroundStyle(planningStatusColor(node.emphasis))
                Text(node.kind)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(node.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if let subtitle = node.subtitle {
                Text(subtitle)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !node.changedFields.isEmpty {
                Text(node.changedFields.prefix(3).joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let geometry = node.geometry {
                designDiffCanvasGeometryPreview(geometry, emphasis: node.emphasis)
            }
        }
        .padding(7)
        .frame(width: 146, alignment: .leading)
        .background(planningStatusColor(node.emphasis).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(planningStatusColor(node.emphasis).opacity(0.55), lineWidth: 1)
        )
    }

    private func designDiffCanvasGeometryPreview(
        _ geometry: RunReviewDesignDiffCanvasGeometrySummary,
        emphasis: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.background.opacity(0.75))
                    if let bounds = designDiffCanvasGeometryBounds(geometry) {
                        if let beforeFrame = geometry.beforeFrame {
                            designDiffCanvasGeometryRect(
                                beforeFrame,
                                bounds: bounds,
                                canvasSize: proxy.size
                            )
                            .stroke(.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        }
                        if let afterFrame = geometry.afterFrame {
                            designDiffCanvasGeometryRect(
                                afterFrame,
                                bounds: bounds,
                                canvasSize: proxy.size
                            )
                            .fill(planningStatusColor(emphasis).opacity(0.16))
                            designDiffCanvasGeometryRect(
                                afterFrame,
                                bounds: bounds,
                                canvasSize: proxy.size
                            )
                            .stroke(planningStatusColor(emphasis).opacity(0.8), lineWidth: 1)
                        }
                    }
                }
            }
            .frame(height: 42)
            Text(designDiffCanvasGeometryText(geometry))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func designDiffCanvasGeometryRect(
        _ frame: RunReviewDesignDiffFrameSummary,
        bounds: RunReviewDesignDiffFrameSummary,
        canvasSize: CGSize
    ) -> Path {
        Path(designDiffCanvasGeometryCGRect(
            frame,
            bounds: bounds,
            canvasSize: canvasSize
        ))
    }

    private func designDiffCanvasGeometryCGRect(
        _ frame: RunReviewDesignDiffFrameSummary,
        bounds: RunReviewDesignDiffFrameSummary,
        canvasSize: CGSize
    ) -> CGRect {
        let margin = 4.0
        let drawableWidth = max(canvasSize.width - margin * 2, 1)
        let drawableHeight = max(canvasSize.height - margin * 2, 1)
        let scale = min(
            drawableWidth / max(bounds.width, 1),
            drawableHeight / max(bounds.height, 1)
        )
        let x = margin + (frame.x - bounds.x) * scale
        let y = margin + (bounds.y + bounds.height - frame.y - frame.height) * scale
        let width = max(frame.width * scale, 1)
        let height = max(frame.height * scale, 1)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func designDiffCanvasPrimitiveLabelPoint(
        _ frame: RunReviewDesignDiffFrameSummary,
        bounds: RunReviewDesignDiffFrameSummary,
        canvasSize: CGSize
    ) -> CGPoint {
        let rect = designDiffCanvasGeometryCGRect(
            frame,
            bounds: bounds,
            canvasSize: canvasSize
        )
        let x = min(max(rect.midX, 18), max(canvasSize.width - 18, 18))
        let y = min(max(rect.minY - 8, 10), max(canvasSize.height - 10, 10))
        return CGPoint(x: x, y: y)
    }

    private func designDiffCanvasGeometryBounds(
        _ geometry: RunReviewDesignDiffCanvasGeometrySummary
    ) -> RunReviewDesignDiffFrameSummary? {
        let frames = [geometry.beforeFrame, geometry.afterFrame].compactMap { $0 }
        guard let first = frames.first else {
            return nil
        }
        let minX = frames.reduce(first.x) { min($0, $1.x) }
        let minY = frames.reduce(first.y) { min($0, $1.y) }
        let maxX = frames.reduce(first.x + first.width) { max($0, $1.x + $1.width) }
        let maxY = frames.reduce(first.y + first.height) { max($0, $1.y + $1.height) }
        return RunReviewDesignDiffFrameSummary(
            x: minX,
            y: minY,
            width: max(maxX - minX, 1),
            height: max(maxY - minY, 1)
        )
    }

    private func designDiffCanvasGeometryText(
        _ geometry: RunReviewDesignDiffCanvasGeometrySummary
    ) -> String {
        guard let delta = geometry.delta else {
            if let afterFrame = geometry.afterFrame {
                return "after \(designDiffCanvasFrameText(afterFrame))"
            }
            if let beforeFrame = geometry.beforeFrame {
                return "before \(designDiffCanvasFrameText(beforeFrame))"
            }
            return geometry.source
        }
        return [
            "dx \(designDiffNumberText(delta.dx))",
            "dy \(designDiffNumberText(delta.dy))",
            "dw \(designDiffNumberText(delta.dWidth))",
            "dh \(designDiffNumberText(delta.dHeight))",
        ].joined(separator: ", ")
    }

    private func designDiffCanvasFrameText(
        _ frame: RunReviewDesignDiffFrameSummary
    ) -> String {
        "x \(designDiffNumberText(frame.x)), y \(designDiffNumberText(frame.y)), w \(designDiffNumberText(frame.width)), h \(designDiffNumberText(frame.height))"
    }

    private func designDiffCanvasNativeHeight(aspectRatio: Double) -> CGFloat {
        let boundedRatio = min(max(aspectRatio, 0.35), 5)
        return min(max(180 / boundedRatio, 96), 190)
    }

    private func designDiffCanvasLayerText(
        _ layer: RunReviewDesignDiffCanvasLayerSummary
    ) -> String {
        let emphasis = layer.emphasisBuckets
            .map { "\($0.label) \($0.count)" }
            .joined(separator: "/")
        let suffix = emphasis.isEmpty ? "" : " \(emphasis)"
        return "\(layer.layerID) \(layer.nodeCount)n \(layer.changedFieldCount)f\(suffix)"
    }

    private func designDiffCanvasPrimitiveText(
        _ primitive: RunReviewDesignDiffCanvasPrimitiveSummary
    ) -> String {
        let layer = primitive.layerID.map { "\($0) " } ?? ""
        return "\(layer)\(primitive.label) \(primitive.changedFieldCount)f"
    }

    private func designDiffNumberText(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        return String(rounded)
    }

    private func designDiffVisualFocusPane(
        _ focus: RunReviewDesignDiffVisualFocus
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            designDiffVisualFocusPreview(focus)
                .frame(width: 72, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    planningStatusBadge(focus.emphasis)
                    Text(focus.kind)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(focus.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let subtitle = focus.subtitle {
                    Text(subtitle)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !focus.changedFields.isEmpty {
                    Text(focus.changedFields.prefix(4).joined(separator: ", "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(6)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func designDiffVisualFocusPreview(
        _ focus: RunReviewDesignDiffVisualFocus
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.secondary.opacity(0.08))
            RoundedRectangle(cornerRadius: 6)
                .stroke(.secondary.opacity(0.18), lineWidth: 1)
            designDiffVisualFocusSymbol(focus)
        }
    }

    @ViewBuilder
    private func designDiffVisualFocusSymbol(
        _ focus: RunReviewDesignDiffVisualFocus
    ) -> some View {
        switch focus.kind {
        case "layout-shape", "layout-route":
            ZStack {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(.secondary.opacity(0.14))
                            .frame(width: 1)
                    }
                }
                RoundedRectangle(cornerRadius: 3)
                    .fill(planningStatusColor(focus.emphasis).opacity(0.35))
                    .frame(width: 42, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(planningStatusColor(focus.emphasis), lineWidth: 1)
                    )
            }
        case "schematic-instance":
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title3)
                .foregroundStyle(planningStatusColor(focus.emphasis))
        case "schematic-net":
            Image(systemName: "waveform.path.ecg")
                .font(.title3)
                .foregroundStyle(planningStatusColor(focus.emphasis))
        default:
            Image(systemName: designDiffVisualFocusIcon(focus.kind))
                .font(.title3)
                .foregroundStyle(planningStatusColor(focus.emphasis))
        }
    }

    private func designDiffVisualFocusIcon(_ kind: String) -> String {
        if kind.hasPrefix("layout") {
            return "square.grid.3x3"
        }
        if kind.hasPrefix("schematic") {
            return "point.3.connected.trianglepath.dotted"
        }
        if kind.hasPrefix("netlist") {
            return "list.bullet.rectangle"
        }
        return "scope"
    }

    private func designDiffPathContextRow(
        _ context: RunReviewDesignDiffPathContext
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: designDiffPathContextIcon(context.scope))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(context.displayName)
                    .font(.caption2.weight(.semibold))
                Spacer()
            }
            let details = designDiffPathContextDetails(context)
            if !details.isEmpty {
                Text(details)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.leading, 8)
    }

    private func designDiffPathContextDetails(
        _ context: RunReviewDesignDiffPathContext
    ) -> String {
        var details: [String] = []
        if let cellID = context.cellID {
            details.append("cell \(cellID)")
        }
        if let collection = context.collection {
            details.append("collection \(collection)")
        }
        if let layerID = context.layerID {
            details.append("layer \(layerID)")
        }
        if let entityID = context.entityID {
            details.append("entity \(entityID)")
        }
        if let propertyPath = context.propertyPath {
            details.append("property \(propertyPath)")
        }
        return details.joined(separator: " / ")
    }

    private func designDiffPathContextIcon(_ scope: String) -> String {
        switch scope.lowercased() {
        case "layout":
            return "square.grid.3x3"
        case "schematic":
            return "point.3.connected.trianglepath.dotted"
        case "netlist":
            return "list.bullet.rectangle"
        default:
            return "scope"
        }
    }

    private func designDiffValueChangeList(
        _ changes: [RunReviewDesignDiffValueChangeSummary]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Field changes")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        planningStatusBadge(change.state)
                        Text(change.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    HStack(alignment: .top, spacing: 8) {
                        designDiffValuePreview("Before", value: change.beforePreview)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        designDiffValuePreview("After", value: change.afterPreview)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.leading, 8)
    }

    private func designDiffValuePreview(
        _ title: String,
        value: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value ?? "not recorded")
                .font(.caption2.monospaced())
                .foregroundStyle(value == nil ? .secondary : .primary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func designDiffArtifactRow(
        _ artifact: RunReviewDesignDiffArtifactSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let artifactID = artifact.artifactID {
                    Text(artifactID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(artifact.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let byteCount = artifact.byteCount {
                    Text("\(byteCount) B")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            if let sha256 = artifact.sha256 {
                Text(sha256)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func planningStatusBadge(_ status: String) -> some View {
        Text(status)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(planningStatusColor(status).opacity(0.14), in: Capsule())
            .foregroundStyle(planningStatusColor(status))
    }

    private func planningStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "passed", "accepted", "approved", "satisfied", "succeeded", "ready", "low", "info", "added":
            return .green
        case "failed", "rejected", "blocked", "error", "missing", "unsupported", "critical", "high",
             "not-accepted", "removed":
            return .red
        case "pending", "needs-review", "approval-required", "incomplete", "medium", "warning", "modified",
             "truncated":
            return .orange
        default:
            return .secondary
        }
    }
}
