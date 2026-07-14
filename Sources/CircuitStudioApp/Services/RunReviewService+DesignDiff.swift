import Foundation
import CircuiteFoundation
import Xcircuite
import DesignFlowKernel

extension RunReviewService {
    func designDiffSummary(from diff: XcircuiteDesignDiff) -> RunReviewDesignDiffSummary {
        let changes = diff.changes.map { change in
            let artifacts = change.artifacts.compactMap(designDiffArtifactSummary)
            let pathContext = designDiffPathContext(
                domain: change.domain.rawValue,
                path: change.path
            )
            let valueChanges = semanticValueChanges(
                before: change.before,
                after: change.after
            )
            let geometry = designDiffCanvasGeometry(
                before: change.before,
                after: change.after
            )
            return RunReviewDesignDiffChangeSummary(
                changeID: change.changeID,
                domain: change.domain.rawValue,
                operation: change.operation.rawValue,
                path: change.path,
                fromPath: change.fromPath,
                summary: change.summary,
                beforePreview: jsonPreview(change.before),
                afterPreview: jsonPreview(change.after),
                pathContext: pathContext,
                visualFocus: designDiffVisualFocus(
                    operation: change.operation.rawValue,
                    pathContext: pathContext,
                    valueChanges: valueChanges
                ),
                valueChanges: valueChanges,
                geometry: geometry,
                artifactCount: artifacts.count,
                artifacts: artifacts
            )
        }
        return RunReviewDesignDiffSummary(
            title: diff.title,
            actor: diff.actor,
            reviewState: diff.reviewState.rawValue,
            changeCount: diff.changes.count,
            domains: buckets(diff.changes.map { $0.domain.rawValue }),
            operations: buckets(diff.changes.map { $0.operation.rawValue }),
            baseSnapshot: diff.baseSnapshot.flatMap(designDiffArtifactSummary),
            proposedSnapshot: diff.proposedSnapshot.flatMap(designDiffArtifactSummary),
            canvases: designDiffCanvases(from: changes),
            changes: changes
        )
    }

    private func buckets(_ labels: [String]) -> [RunReviewDesignDiffBucket] {
        let counts = labels.reduce(into: [String: Int]()) { result, label in
            result[label, default: 0] += 1
        }
        return counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .map { RunReviewDesignDiffBucket(label: $0.key, count: $0.value) }
    }

    private func designDiffArtifactSummary(
        _ reference: XcircuiteFileReference
    ) -> RunReviewDesignDiffArtifactSummary? {
        guard let foundationReference = FoundationArtifactTypeProjection.reference(reference) else {
            return nil
        }
        return designDiffArtifactSummary(foundationReference)
    }

    private func designDiffArtifactSummary(
        _ reference: ArtifactReference
    ) -> RunReviewDesignDiffArtifactSummary {
        RunReviewDesignDiffArtifactSummary(
            artifactID: reference.id.rawValue,
            path: reference.path,
            sha256: reference.digest.hexadecimalValue,
            byteCount: Int64(clamping: reference.byteCount)
        )
    }

    private func jsonPreview(_ value: XcircuiteJSONValue?) -> String? {
        guard let value else {
            return nil
        }
        return bounded(jsonPreview(value, depth: 0), limit: 160)
    }

    private func designDiffPathContext(
        domain: String,
        path: String
    ) -> RunReviewDesignDiffPathContext? {
        let segments = designDiffPathSegments(path)
        guard !segments.isEmpty else {
            return nil
        }
        let cellID = segment(after: "cells", in: segments)
        if let layoutIndex = segments.firstIndex(of: "layout") {
            return designDiffSectionContext(
                scope: "layout",
                sectionIndex: layoutIndex,
                cellID: cellID,
                segments: segments
            )
        }
        if let schematicIndex = segments.firstIndex(of: "schematic") {
            return designDiffSectionContext(
                scope: "schematic",
                sectionIndex: schematicIndex,
                cellID: cellID,
                segments: segments
            )
        }
        if let netlistIndex = segments.firstIndex(of: "netlist") {
            return designDiffSectionContext(
                scope: "netlist",
                sectionIndex: netlistIndex,
                cellID: cellID,
                segments: segments
            )
        }
        let entityID = segments.last
        return RunReviewDesignDiffPathContext(
            scope: domain,
            displayName: designDiffDisplayName(scope: domain, collection: nil, entityID: entityID),
            cellID: cellID,
            entityID: entityID
        )
    }

    private func designDiffSectionContext(
        scope: String,
        sectionIndex: Int,
        cellID: String?,
        segments: [String]
    ) -> RunReviewDesignDiffPathContext {
        let collection = segment(in: segments, at: sectionIndex + 1)
        let layerID: String?
        let entityID: String?
        let propertyStartIndex: Int
        if collection == "shapes" || collection == "routes" {
            layerID = segment(in: segments, at: sectionIndex + 2)
            entityID = segment(in: segments, at: sectionIndex + 3)
            propertyStartIndex = sectionIndex + 4
        } else {
            layerID = nil
            entityID = segment(in: segments, at: sectionIndex + 2)
            propertyStartIndex = sectionIndex + 3
        }
        return RunReviewDesignDiffPathContext(
            scope: scope,
            displayName: designDiffDisplayName(
                scope: scope,
                collection: collection,
                entityID: entityID
            ),
            cellID: cellID,
            collection: collection,
            layerID: layerID,
            entityID: entityID,
            propertyPath: propertyPath(in: segments, startingAt: propertyStartIndex)
        )
    }

    private func designDiffDisplayName(
        scope: String,
        collection: String?,
        entityID: String?
    ) -> String {
        [scope, collection, entityID]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func designDiffPathSegments(_ path: String) -> [String] {
        path
            .split(separator: "/")
            .map(String.init)
            .map(jsonPointerUnescaped)
    }

    private func jsonPointerUnescaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "~1", with: "/")
            .replacingOccurrences(of: "~0", with: "~")
    }

    private func segment(after marker: String, in segments: [String]) -> String? {
        guard let index = segments.firstIndex(of: marker) else {
            return nil
        }
        return segment(in: segments, at: index + 1)
    }

    private func segment(in segments: [String], at index: Int) -> String? {
        guard segments.indices.contains(index) else {
            return nil
        }
        return segments[index]
    }

    private func propertyPath(in segments: [String], startingAt index: Int) -> String? {
        guard segments.indices.contains(index) else {
            return nil
        }
        return segments[index...].joined(separator: "/")
    }

    private func designDiffVisualFocus(
        operation: String,
        pathContext: RunReviewDesignDiffPathContext?,
        valueChanges: [RunReviewDesignDiffValueChangeSummary]
    ) -> RunReviewDesignDiffVisualFocus? {
        guard let pathContext else {
            return nil
        }
        let title = pathContext.entityID ?? pathContext.displayName
        return RunReviewDesignDiffVisualFocus(
            kind: designDiffVisualFocusKind(pathContext),
            title: title,
            subtitle: designDiffVisualFocusSubtitle(pathContext),
            emphasis: designDiffVisualFocusEmphasis(
                operation: operation,
                valueChanges: valueChanges
            ),
            changedFields: designDiffVisualFocusChangedFields(
                pathContext: pathContext,
                valueChanges: valueChanges
            )
        )
    }

    private func designDiffVisualFocusChangedFields(
        pathContext: RunReviewDesignDiffPathContext,
        valueChanges: [RunReviewDesignDiffValueChangeSummary]
    ) -> [String] {
        let fields = valueChanges
            .map(\.path)
            .filter { $0 != "/" && $0 != "..." }
        if !fields.isEmpty {
            return fields
        }
        if let propertyPath = pathContext.propertyPath {
            return [propertyPath]
        }
        return []
    }

    private func designDiffVisualFocusKind(
        _ context: RunReviewDesignDiffPathContext
    ) -> String {
        switch (context.scope, context.collection) {
        case ("layout", "shapes"):
            return "layout-shape"
        case ("layout", "routes"):
            return "layout-route"
        case ("layout", "pins"):
            return "layout-pin"
        case ("layout", "labels"):
            return "layout-label"
        case ("schematic", "instances"):
            return "schematic-instance"
        case ("schematic", "nets"):
            return "schematic-net"
        case ("netlist", _):
            return "netlist-entity"
        default:
            return "\(context.scope)-entity"
        }
    }

    private func designDiffVisualFocusSubtitle(
        _ context: RunReviewDesignDiffPathContext
    ) -> String? {
        var parts: [String] = []
        if let cellID = context.cellID {
            parts.append(cellID)
        }
        if let layerID = context.layerID {
            parts.append(layerID)
        }
        if let collection = context.collection {
            parts.append(collection)
        }
        if let propertyPath = context.propertyPath {
            parts.append(propertyPath)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    private func designDiffVisualFocusEmphasis(
        operation: String,
        valueChanges: [RunReviewDesignDiffValueChangeSummary]
    ) -> String {
        if operation == "add" {
            return "added"
        }
        if operation == "remove" {
            return "removed"
        }
        let states = Set(valueChanges.map(\.state))
        if states == ["added"] {
            return "added"
        }
        if states == ["removed"] {
            return "removed"
        }
        return "modified"
    }

    private func designDiffCanvases(
        from changes: [RunReviewDesignDiffChangeSummary]
    ) -> [RunReviewDesignDiffCanvasSummary] {
        let grouped = Dictionary(grouping: changes) { change in
            designDiffCanvasID(for: change.pathContext, domain: change.domain)
        }
        return grouped.keys.sorted().compactMap { canvasID in
            guard let changes = grouped[canvasID] else {
                return nil
            }
            let nodes = designDiffCanvasNodes(from: changes)
            guard !nodes.isEmpty else {
                return nil
            }
            let firstContext = changes.compactMap(\.pathContext).first
            let changedFieldCount = nodes.reduce(0) { result, node in
                result + node.changedFields.count
            }
            let viewport = designDiffCanvasViewport(from: nodes)
            return RunReviewDesignDiffCanvasSummary(
                canvasID: canvasID,
                scope: firstContext?.scope ?? changes.first?.domain ?? "unknown",
                cellID: firstContext?.cellID,
                title: designDiffCanvasTitle(context: firstContext, fallback: canvasID),
                nodeCount: nodes.count,
                changedFieldCount: changedFieldCount,
                viewport: viewport,
                rendering: designDiffCanvasRendering(
                    scope: firstContext?.scope ?? changes.first?.domain ?? "unknown",
                    viewport: viewport,
                    nodes: nodes
                ),
                nodes: nodes
            )
        }
    }

    private func designDiffCanvasID(
        for context: RunReviewDesignDiffPathContext?,
        domain: String
    ) -> String {
        let scope = context?.scope ?? domain
        let cellID = context?.cellID ?? "top"
        return "\(scope):\(cellID)"
    }

    private func designDiffCanvasTitle(
        context: RunReviewDesignDiffPathContext?,
        fallback: String
    ) -> String {
        guard let context else {
            return fallback
        }
        if let cellID = context.cellID {
            return "\(context.scope) \(cellID)"
        }
        return context.scope
    }

    private func designDiffCanvasNodes(
        from changes: [RunReviewDesignDiffChangeSummary]
    ) -> [RunReviewDesignDiffCanvasNodeSummary] {
        let keyedChanges = Dictionary(grouping: changes) { change in
            designDiffCanvasNodeID(change)
        }
        return keyedChanges.keys.sorted().compactMap { nodeID in
            guard let nodeChanges = keyedChanges[nodeID],
                  let firstChange = nodeChanges.first,
                  let focus = firstChange.visualFocus else {
                return nil
            }
            let context = firstChange.pathContext
            let changedFields = Array(
                Set(nodeChanges.flatMap { $0.visualFocus?.changedFields ?? [] })
            ).sorted()
            return RunReviewDesignDiffCanvasNodeSummary(
                nodeID: nodeID,
                kind: focus.kind,
                title: focus.title,
                subtitle: focus.subtitle,
                emphasis: designDiffMergedEmphasis(
                    nodeChanges.compactMap { $0.visualFocus?.emphasis }
                ),
                layerID: context?.layerID,
                entityID: context?.entityID,
                changedFields: changedFields,
                geometry: designDiffMergedCanvasGeometry(
                    nodeChanges.compactMap(\.geometry)
                )
            )
        }
    }

    private func designDiffCanvasNodeID(_ change: RunReviewDesignDiffChangeSummary) -> String {
        guard let context = change.pathContext else {
            return change.changeID
        }
        return [
            context.scope,
            context.cellID ?? "top",
            context.collection ?? "entity",
            context.layerID,
            context.entityID ?? change.changeID,
        ]
        .compactMap { $0 }
        .joined(separator: ":")
    }

    private func designDiffMergedEmphasis(_ emphases: [String]) -> String {
        if emphases.contains("removed") {
            return "removed"
        }
        if emphases.contains("added") {
            return "added"
        }
        if emphases.contains("modified") {
            return "modified"
        }
        return emphases.first ?? "modified"
    }

    private func designDiffCanvasGeometry(
        before: XcircuiteJSONValue?,
        after: XcircuiteJSONValue?
    ) -> RunReviewDesignDiffCanvasGeometrySummary? {
        let beforeCandidate = designDiffFrameCandidate(from: before)
        let afterCandidate = designDiffFrameCandidate(from: after)
        guard beforeCandidate != nil || afterCandidate != nil else {
            return nil
        }
        let beforeFrame = beforeCandidate?.frame
        let afterFrame = afterCandidate?.frame
        return RunReviewDesignDiffCanvasGeometrySummary(
            source: designDiffGeometrySource(
                before: beforeCandidate?.source,
                after: afterCandidate?.source
            ),
            beforeFrame: beforeFrame,
            afterFrame: afterFrame,
            delta: designDiffFrameDelta(before: beforeFrame, after: afterFrame)
        )
    }

    private func designDiffMergedCanvasGeometry(
        _ geometries: [RunReviewDesignDiffCanvasGeometrySummary]
    ) -> RunReviewDesignDiffCanvasGeometrySummary? {
        guard !geometries.isEmpty else {
            return nil
        }
        let beforeFrame = designDiffEnclosingFrame(
            geometries.compactMap(\.beforeFrame)
        )
        let afterFrame = designDiffEnclosingFrame(
            geometries.compactMap(\.afterFrame)
        )
        let sources = Array(Set(geometries.map(\.source))).sorted()
        return RunReviewDesignDiffCanvasGeometrySummary(
            source: sources.joined(separator: "+"),
            beforeFrame: beforeFrame,
            afterFrame: afterFrame,
            delta: designDiffFrameDelta(before: beforeFrame, after: afterFrame)
        )
    }

    private func designDiffCanvasViewport(
        from nodes: [RunReviewDesignDiffCanvasNodeSummary]
    ) -> RunReviewDesignDiffCanvasViewportSummary? {
        let geometryNodes = nodes.filter { $0.geometry != nil }
        guard !geometryNodes.isEmpty else {
            return nil
        }
        let geometries = geometryNodes.compactMap(\.geometry)
        let beforeBounds = designDiffEnclosingFrame(
            geometries.compactMap(\.beforeFrame)
        )
        let afterBounds = designDiffEnclosingFrame(
            geometries.compactMap(\.afterFrame)
        )
        guard let bounds = designDiffEnclosingFrame(
            [beforeBounds, afterBounds].compactMap { $0 }
        ) else {
            return nil
        }
        return RunReviewDesignDiffCanvasViewportSummary(
            bounds: bounds,
            beforeBounds: beforeBounds,
            afterBounds: afterBounds,
            geometryNodeCount: geometryNodes.count,
            sources: Array(Set(geometries.map(\.source))).sorted(),
            layerIDs: Array(Set(geometryNodes.compactMap(\.layerID))).sorted()
        )
    }

    private func designDiffCanvasRendering(
        scope: String,
        viewport: RunReviewDesignDiffCanvasViewportSummary?,
        nodes: [RunReviewDesignDiffCanvasNodeSummary]
    ) -> RunReviewDesignDiffCanvasRenderingSummary? {
        guard let viewport else {
            return nil
        }
        let geometryNodes = nodes.filter { $0.geometry != nil }
        guard !geometryNodes.isEmpty else {
            return nil
        }
        let beforePrimitiveCount = geometryNodes.filter {
            $0.geometry?.beforeFrame != nil
        }.count
        let afterPrimitiveCount = geometryNodes.filter {
            $0.geometry?.afterFrame != nil
        }.count
        let overlayPrimitiveCount = geometryNodes.filter {
            $0.geometry?.beforeFrame != nil && $0.geometry?.afterFrame != nil
        }.count
        return RunReviewDesignDiffCanvasRenderingSummary(
            coordinateSpace: designDiffCanvasCoordinateSpace(scope),
            aspectRatio: viewport.bounds.width / max(viewport.bounds.height, 1),
            beforePrimitiveCount: beforePrimitiveCount,
            afterPrimitiveCount: afterPrimitiveCount,
            overlayPrimitiveCount: overlayPrimitiveCount,
            layers: designDiffCanvasLayers(from: geometryNodes),
            primitives: designDiffCanvasPrimitives(from: geometryNodes)
        )
    }

    private func designDiffCanvasCoordinateSpace(_ scope: String) -> String {
        switch scope {
        case "layout":
            return "layout-native"
        case "schematic":
            return "schematic-native"
        default:
            return "\(scope)-native"
        }
    }

    private func designDiffCanvasLayers(
        from nodes: [RunReviewDesignDiffCanvasNodeSummary]
    ) -> [RunReviewDesignDiffCanvasLayerSummary] {
        let grouped = Dictionary(grouping: nodes) { node in
            node.layerID ?? "unlayered"
        }
        return grouped.keys.sorted().compactMap { layerID in
            guard let layerNodes = grouped[layerID] else {
                return nil
            }
            let changedFieldCount = layerNodes.reduce(0) { result, node in
                result + node.changedFields.count
            }
            return RunReviewDesignDiffCanvasLayerSummary(
                layerID: layerID,
                nodeCount: layerNodes.count,
                changedFieldCount: changedFieldCount,
                beforePrimitiveCount: layerNodes.filter { $0.geometry?.beforeFrame != nil }.count,
                afterPrimitiveCount: layerNodes.filter { $0.geometry?.afterFrame != nil }.count,
                emphasisBuckets: buckets(layerNodes.map(\.emphasis))
            )
        }
    }

    private func designDiffCanvasPrimitives(
        from nodes: [RunReviewDesignDiffCanvasNodeSummary]
    ) -> [RunReviewDesignDiffCanvasPrimitiveSummary] {
        nodes.sorted { $0.nodeID < $1.nodeID }.compactMap { node in
            guard let geometry = node.geometry else {
                return nil
            }
            let selectionFrame = geometry.afterFrame ?? geometry.beforeFrame
            return RunReviewDesignDiffCanvasPrimitiveSummary(
                primitiveID: node.nodeID,
                nodeID: node.nodeID,
                label: node.entityID ?? node.title,
                layerID: node.layerID,
                emphasis: node.emphasis,
                changedFieldCount: node.changedFields.count,
                beforeFrame: geometry.beforeFrame,
                afterFrame: geometry.afterFrame,
                selectionFrame: selectionFrame
            )
        }
    }

    private func designDiffFrameCandidate(
        from value: XcircuiteJSONValue?,
        sourceHint: String? = nil
    ) -> (source: String, frame: RunReviewDesignDiffFrameSummary)? {
        guard let value else {
            return nil
        }
        switch value {
        case .object(let object):
            for key in ["geometry", "frame", "bounds", "bbox", "rect"] {
                guard let nested = object[key],
                      let candidate = designDiffFrameCandidate(from: nested, sourceHint: key)
                else {
                    continue
                }
                return (
                    source: designDiffPrefixedSource(key, candidate.source),
                    frame: candidate.frame
                )
            }
            if let frame = designDiffOriginSizeFrame(from: object) {
                return (source: sourceHint ?? "origin-size", frame: frame)
            }
            if let frame = designDiffXYWHFrame(from: object) {
                return (source: sourceHint ?? "xywh", frame: frame)
            }
            if let frame = designDiffCornerFrame(from: object) {
                return (source: sourceHint ?? "corners", frame: frame)
            }
            return nil
        case .array(let values):
            return designDiffArrayFrame(from: values, sourceHint: sourceHint)
        default:
            return nil
        }
    }

    private func designDiffOriginSizeFrame(
        from object: [String: XcircuiteJSONValue]
    ) -> RunReviewDesignDiffFrameSummary? {
        guard case .object(let origin)? = object["origin"],
              case .object(let size)? = object["size"],
              let x = designDiffNumber(origin["x"]),
              let y = designDiffNumber(origin["y"]),
              let width = designDiffFirstNumber(size, keys: ["width", "w"]),
              let height = designDiffFirstNumber(size, keys: ["height", "h"])
        else {
            return nil
        }
        return designDiffFrame(x: x, y: y, width: width, height: height)
    }

    private func designDiffXYWHFrame(
        from object: [String: XcircuiteJSONValue]
    ) -> RunReviewDesignDiffFrameSummary? {
        guard let x = designDiffFirstNumber(object, keys: ["x", "minX"]),
              let y = designDiffFirstNumber(object, keys: ["y", "minY"]),
              let width = designDiffFirstNumber(object, keys: ["width", "w"]),
              let height = designDiffFirstNumber(object, keys: ["height", "h"])
        else {
            return nil
        }
        return designDiffFrame(x: x, y: y, width: width, height: height)
    }

    private func designDiffCornerFrame(
        from object: [String: XcircuiteJSONValue]
    ) -> RunReviewDesignDiffFrameSummary? {
        guard let x1 = designDiffFirstNumber(object, keys: ["x1", "minX", "left"]),
              let y1 = designDiffFirstNumber(object, keys: ["y1", "minY", "bottom"]),
              let x2 = designDiffFirstNumber(object, keys: ["x2", "maxX", "right"]),
              let y2 = designDiffFirstNumber(object, keys: ["y2", "maxY", "top"])
        else {
            return nil
        }
        return designDiffFrame(
            x: min(x1, x2),
            y: min(y1, y2),
            width: abs(x2 - x1),
            height: abs(y2 - y1)
        )
    }

    private func designDiffArrayFrame(
        from values: [XcircuiteJSONValue],
        sourceHint: String?
    ) -> (source: String, frame: RunReviewDesignDiffFrameSummary)? {
        guard values.count == 4 else {
            return nil
        }
        let numbers = values.compactMap(designDiffNumber)
        guard numbers.count == 4 else {
            return nil
        }
        if sourceHint == "bbox" || sourceHint == "bounds" {
            guard let frame = designDiffFrame(
                x: min(numbers[0], numbers[2]),
                y: min(numbers[1], numbers[3]),
                width: abs(numbers[2] - numbers[0]),
                height: abs(numbers[3] - numbers[1])
            ) else {
                return nil
            }
            return (
                source: sourceHint ?? "corners-array",
                frame: frame
            )
        }
        guard let frame = designDiffFrame(
            x: numbers[0],
            y: numbers[1],
            width: numbers[2],
            height: numbers[3]
        ) else {
            return nil
        }
        return (
            source: sourceHint ?? "xywh-array",
            frame: frame
        )
    }

    private func designDiffFirstNumber(
        _ object: [String: XcircuiteJSONValue],
        keys: [String]
    ) -> Double? {
        for key in keys {
            if let number = designDiffNumber(object[key]) {
                return number
            }
        }
        return nil
    }

    private func designDiffNumber(_ value: XcircuiteJSONValue?) -> Double? {
        guard case .number(let number)? = value, number.isFinite else {
            return nil
        }
        return number
    }

    private func designDiffFrame(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> RunReviewDesignDiffFrameSummary? {
        guard x.isFinite,
              y.isFinite,
              width.isFinite,
              height.isFinite,
              width >= 0,
              height >= 0
        else {
            return nil
        }
        return RunReviewDesignDiffFrameSummary(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }

    private func designDiffEnclosingFrame(
        _ frames: [RunReviewDesignDiffFrameSummary]
    ) -> RunReviewDesignDiffFrameSummary? {
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
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private func designDiffFrameDelta(
        before: RunReviewDesignDiffFrameSummary?,
        after: RunReviewDesignDiffFrameSummary?
    ) -> RunReviewDesignDiffFrameDeltaSummary? {
        guard let before,
              let after
        else {
            return nil
        }
        return RunReviewDesignDiffFrameDeltaSummary(
            dx: after.x - before.x,
            dy: after.y - before.y,
            dWidth: after.width - before.width,
            dHeight: after.height - before.height
        )
    }

    private func designDiffGeometrySource(
        before: String?,
        after: String?
    ) -> String {
        switch (before, after) {
        case let (.some(before), .some(after)) where before == after:
            return before
        case let (.some(before), .some(after)):
            return "\(before)->\(after)"
        case let (.some(before), nil):
            return before
        case let (nil, .some(after)):
            return after
        default:
            return "unknown"
        }
    }

    private func designDiffPrefixedSource(_ prefix: String, _ source: String) -> String {
        source == prefix ? source : "\(prefix).\(source)"
    }

    private func semanticValueChanges(
        before: XcircuiteJSONValue?,
        after: XcircuiteJSONValue?
    ) -> [RunReviewDesignDiffValueChangeSummary] {
        var changes: [RunReviewDesignDiffValueChangeSummary] = []
        var truncated = false
        collectSemanticValueChanges(
            path: "",
            before: before,
            after: after,
            changes: &changes,
            truncated: &truncated
        )
        if truncated {
            changes.append(
                RunReviewDesignDiffValueChangeSummary(
                    path: "...",
                    state: "truncated"
                )
            )
        }
        return changes
    }

    private func collectSemanticValueChanges(
        path: String,
        before: XcircuiteJSONValue?,
        after: XcircuiteJSONValue?,
        changes: inout [RunReviewDesignDiffValueChangeSummary],
        truncated: inout Bool
    ) {
        guard !truncated, before != after else {
            return
        }
        if let before,
           let after,
           case .object(let beforeObject) = before,
           case .object(let afterObject) = after {
            let keys = Set(beforeObject.keys).union(Set(afterObject.keys)).sorted()
            for key in keys {
                collectSemanticValueChanges(
                    path: jsonPointerPath(parent: path, key: key),
                    before: beforeObject[key],
                    after: afterObject[key],
                    changes: &changes,
                    truncated: &truncated
                )
            }
            return
        }
        guard changes.count < Self.semanticValueChangeLimit else {
            truncated = true
            return
        }
        changes.append(
            RunReviewDesignDiffValueChangeSummary(
                path: path.isEmpty ? "/" : path,
                state: semanticValueChangeState(before: before, after: after),
                beforePreview: jsonPreview(before),
                afterPreview: jsonPreview(after)
            )
        )
    }

    private func semanticValueChangeState(
        before: XcircuiteJSONValue?,
        after: XcircuiteJSONValue?
    ) -> String {
        switch (before, after) {
        case (nil, .some(_)):
            return "added"
        case (.some(_), nil):
            return "removed"
        default:
            return "modified"
        }
    }

    private func jsonPointerPath(parent: String, key: String) -> String {
        let escaped = key
            .replacingOccurrences(of: "~", with: "~0")
            .replacingOccurrences(of: "/", with: "~1")
        return parent.isEmpty ? "/\(escaped)" : "\(parent)/\(escaped)"
    }

    private func jsonPreview(_ value: XcircuiteJSONValue, depth: Int) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            return String(value)
        case .string(let value):
            return "\"\(bounded(value, limit: 80))\""
        case .array(let values):
            if depth >= 1 {
                return "[\(values.count) item(s)]"
            }
            let preview = values.prefix(3).map { jsonPreview($0, depth: depth + 1) }.joined(separator: ", ")
            return "[\(preview)\(values.count > 3 ? ", ..." : "")]"
        case .object(let object):
            let keys = object.keys.sorted()
            if depth >= 1 {
                return "{\(keys.prefix(6).joined(separator: ", "))\(keys.count > 6 ? ", ..." : "")}"
            }
            let preview = keys.prefix(4).map { key in
                "\(key): \(jsonPreview(object[key] ?? .null, depth: depth + 1))"
            }.joined(separator: ", ")
            return "{\(preview)\(keys.count > 4 ? ", ..." : "")}"
        }
    }

    private func bounded(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        let end = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<end]) + "..."
    }

    private static let semanticValueChangeLimit = 32

}
