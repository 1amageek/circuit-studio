import Foundation

public struct RunReviewDesignDiffSummary: Sendable, Hashable {
    public let title: String
    public let actor: String
    public let reviewState: String
    public let changeCount: Int
    public let domains: [RunReviewDesignDiffBucket]
    public let operations: [RunReviewDesignDiffBucket]
    public let baseSnapshot: RunReviewDesignDiffArtifactSummary?
    public let proposedSnapshot: RunReviewDesignDiffArtifactSummary?
    public let canvases: [RunReviewDesignDiffCanvasSummary]
    public let changes: [RunReviewDesignDiffChangeSummary]

    public init(
        title: String,
        actor: String,
        reviewState: String,
        changeCount: Int,
        domains: [RunReviewDesignDiffBucket],
        operations: [RunReviewDesignDiffBucket],
        baseSnapshot: RunReviewDesignDiffArtifactSummary? = nil,
        proposedSnapshot: RunReviewDesignDiffArtifactSummary? = nil,
        canvases: [RunReviewDesignDiffCanvasSummary] = [],
        changes: [RunReviewDesignDiffChangeSummary]
    ) {
        self.title = title
        self.actor = actor
        self.reviewState = reviewState
        self.changeCount = changeCount
        self.domains = domains
        self.operations = operations
        self.baseSnapshot = baseSnapshot
        self.proposedSnapshot = proposedSnapshot
        self.canvases = canvases
        self.changes = changes
    }
}

public struct RunReviewDesignDiffBucket: Sendable, Hashable {
    public let label: String
    public let count: Int

    public init(label: String, count: Int) {
        self.label = label
        self.count = count
    }
}

public struct RunReviewDesignDiffArtifactSummary: Sendable, Hashable {
    public let artifactID: String?
    public let path: String
    public let sha256: String?
    public let byteCount: Int64?

    public init(
        artifactID: String?,
        path: String,
        sha256: String?,
        byteCount: Int64?
    ) {
        self.artifactID = artifactID
        self.path = path
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

public struct RunReviewDesignDiffCanvasSummary: Sendable, Hashable {
    public let canvasID: String
    public let scope: String
    public let cellID: String?
    public let title: String
    public let nodeCount: Int
    public let changedFieldCount: Int
    public let viewport: RunReviewDesignDiffCanvasViewportSummary?
    public let rendering: RunReviewDesignDiffCanvasRenderingSummary?
    public let nodes: [RunReviewDesignDiffCanvasNodeSummary]

    public init(
        canvasID: String,
        scope: String,
        cellID: String? = nil,
        title: String,
        nodeCount: Int,
        changedFieldCount: Int,
        viewport: RunReviewDesignDiffCanvasViewportSummary? = nil,
        rendering: RunReviewDesignDiffCanvasRenderingSummary? = nil,
        nodes: [RunReviewDesignDiffCanvasNodeSummary]
    ) {
        self.canvasID = canvasID
        self.scope = scope
        self.cellID = cellID
        self.title = title
        self.nodeCount = nodeCount
        self.changedFieldCount = changedFieldCount
        self.viewport = viewport
        self.rendering = rendering
        self.nodes = nodes
    }
}

public struct RunReviewDesignDiffCanvasViewportSummary: Sendable, Hashable {
    public let bounds: RunReviewDesignDiffFrameSummary
    public let beforeBounds: RunReviewDesignDiffFrameSummary?
    public let afterBounds: RunReviewDesignDiffFrameSummary?
    public let geometryNodeCount: Int
    public let sources: [String]
    public let layerIDs: [String]

    public init(
        bounds: RunReviewDesignDiffFrameSummary,
        beforeBounds: RunReviewDesignDiffFrameSummary? = nil,
        afterBounds: RunReviewDesignDiffFrameSummary? = nil,
        geometryNodeCount: Int,
        sources: [String] = [],
        layerIDs: [String] = []
    ) {
        self.bounds = bounds
        self.beforeBounds = beforeBounds
        self.afterBounds = afterBounds
        self.geometryNodeCount = geometryNodeCount
        self.sources = sources
        self.layerIDs = layerIDs
    }
}

public struct RunReviewDesignDiffCanvasRenderingSummary: Sendable, Hashable {
    public let coordinateSpace: String
    public let aspectRatio: Double
    public let beforePrimitiveCount: Int
    public let afterPrimitiveCount: Int
    public let overlayPrimitiveCount: Int
    public let layers: [RunReviewDesignDiffCanvasLayerSummary]
    public let primitives: [RunReviewDesignDiffCanvasPrimitiveSummary]

    public init(
        coordinateSpace: String,
        aspectRatio: Double,
        beforePrimitiveCount: Int,
        afterPrimitiveCount: Int,
        overlayPrimitiveCount: Int,
        layers: [RunReviewDesignDiffCanvasLayerSummary],
        primitives: [RunReviewDesignDiffCanvasPrimitiveSummary] = []
    ) {
        self.coordinateSpace = coordinateSpace
        self.aspectRatio = aspectRatio
        self.beforePrimitiveCount = beforePrimitiveCount
        self.afterPrimitiveCount = afterPrimitiveCount
        self.overlayPrimitiveCount = overlayPrimitiveCount
        self.layers = layers
        self.primitives = primitives
    }
}

public struct RunReviewDesignDiffCanvasLayerSummary: Sendable, Hashable {
    public let layerID: String
    public let nodeCount: Int
    public let changedFieldCount: Int
    public let beforePrimitiveCount: Int
    public let afterPrimitiveCount: Int
    public let emphasisBuckets: [RunReviewDesignDiffBucket]

    public init(
        layerID: String,
        nodeCount: Int,
        changedFieldCount: Int,
        beforePrimitiveCount: Int,
        afterPrimitiveCount: Int,
        emphasisBuckets: [RunReviewDesignDiffBucket]
    ) {
        self.layerID = layerID
        self.nodeCount = nodeCount
        self.changedFieldCount = changedFieldCount
        self.beforePrimitiveCount = beforePrimitiveCount
        self.afterPrimitiveCount = afterPrimitiveCount
        self.emphasisBuckets = emphasisBuckets
    }
}

public struct RunReviewDesignDiffCanvasPrimitiveSummary: Sendable, Hashable {
    public let primitiveID: String
    public let nodeID: String
    public let label: String
    public let layerID: String?
    public let emphasis: String
    public let changedFieldCount: Int
    public let beforeFrame: RunReviewDesignDiffFrameSummary?
    public let afterFrame: RunReviewDesignDiffFrameSummary?
    public let selectionFrame: RunReviewDesignDiffFrameSummary?

    public init(
        primitiveID: String,
        nodeID: String,
        label: String,
        layerID: String? = nil,
        emphasis: String,
        changedFieldCount: Int,
        beforeFrame: RunReviewDesignDiffFrameSummary? = nil,
        afterFrame: RunReviewDesignDiffFrameSummary? = nil,
        selectionFrame: RunReviewDesignDiffFrameSummary? = nil
    ) {
        self.primitiveID = primitiveID
        self.nodeID = nodeID
        self.label = label
        self.layerID = layerID
        self.emphasis = emphasis
        self.changedFieldCount = changedFieldCount
        self.beforeFrame = beforeFrame
        self.afterFrame = afterFrame
        self.selectionFrame = selectionFrame
    }
}

public struct RunReviewDesignDiffCanvasNodeSummary: Sendable, Hashable {
    public let nodeID: String
    public let kind: String
    public let title: String
    public let subtitle: String?
    public let emphasis: String
    public let layerID: String?
    public let entityID: String?
    public let changedFields: [String]
    public let geometry: RunReviewDesignDiffCanvasGeometrySummary?

    public init(
        nodeID: String,
        kind: String,
        title: String,
        subtitle: String? = nil,
        emphasis: String,
        layerID: String? = nil,
        entityID: String? = nil,
        changedFields: [String] = [],
        geometry: RunReviewDesignDiffCanvasGeometrySummary? = nil
    ) {
        self.nodeID = nodeID
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.emphasis = emphasis
        self.layerID = layerID
        self.entityID = entityID
        self.changedFields = changedFields
        self.geometry = geometry
    }
}

public struct RunReviewDesignDiffCanvasGeometrySummary: Sendable, Hashable {
    public let source: String
    public let beforeFrame: RunReviewDesignDiffFrameSummary?
    public let afterFrame: RunReviewDesignDiffFrameSummary?
    public let delta: RunReviewDesignDiffFrameDeltaSummary?

    public init(
        source: String,
        beforeFrame: RunReviewDesignDiffFrameSummary? = nil,
        afterFrame: RunReviewDesignDiffFrameSummary? = nil,
        delta: RunReviewDesignDiffFrameDeltaSummary? = nil
    ) {
        self.source = source
        self.beforeFrame = beforeFrame
        self.afterFrame = afterFrame
        self.delta = delta
    }
}

public struct RunReviewDesignDiffFrameSummary: Sendable, Hashable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct RunReviewDesignDiffFrameDeltaSummary: Sendable, Hashable {
    public let dx: Double
    public let dy: Double
    public let dWidth: Double
    public let dHeight: Double

    public init(
        dx: Double,
        dy: Double,
        dWidth: Double,
        dHeight: Double
    ) {
        self.dx = dx
        self.dy = dy
        self.dWidth = dWidth
        self.dHeight = dHeight
    }
}

public struct RunReviewDesignDiffChangeSummary: Sendable, Hashable {
    public let changeID: String
    public let domain: String
    public let operation: String
    public let path: String
    public let fromPath: String?
    public let summary: String
    public let beforePreview: String?
    public let afterPreview: String?
    public let pathContext: RunReviewDesignDiffPathContext?
    public let visualFocus: RunReviewDesignDiffVisualFocus?
    public let valueChanges: [RunReviewDesignDiffValueChangeSummary]
    public let geometry: RunReviewDesignDiffCanvasGeometrySummary?
    public let artifactCount: Int
    public let artifacts: [RunReviewDesignDiffArtifactSummary]

    public init(
        changeID: String,
        domain: String,
        operation: String,
        path: String,
        fromPath: String? = nil,
        summary: String,
        beforePreview: String? = nil,
        afterPreview: String? = nil,
        pathContext: RunReviewDesignDiffPathContext? = nil,
        visualFocus: RunReviewDesignDiffVisualFocus? = nil,
        valueChanges: [RunReviewDesignDiffValueChangeSummary] = [],
        geometry: RunReviewDesignDiffCanvasGeometrySummary? = nil,
        artifactCount: Int,
        artifacts: [RunReviewDesignDiffArtifactSummary]
    ) {
        self.changeID = changeID
        self.domain = domain
        self.operation = operation
        self.path = path
        self.fromPath = fromPath
        self.summary = summary
        self.beforePreview = beforePreview
        self.afterPreview = afterPreview
        self.pathContext = pathContext
        self.visualFocus = visualFocus
        self.valueChanges = valueChanges
        self.geometry = geometry
        self.artifactCount = artifactCount
        self.artifacts = artifacts
    }
}

public struct RunReviewDesignDiffPathContext: Sendable, Hashable {
    public let scope: String
    public let displayName: String
    public let cellID: String?
    public let collection: String?
    public let layerID: String?
    public let entityID: String?
    public let propertyPath: String?

    public init(
        scope: String,
        displayName: String,
        cellID: String? = nil,
        collection: String? = nil,
        layerID: String? = nil,
        entityID: String? = nil,
        propertyPath: String? = nil
    ) {
        self.scope = scope
        self.displayName = displayName
        self.cellID = cellID
        self.collection = collection
        self.layerID = layerID
        self.entityID = entityID
        self.propertyPath = propertyPath
    }
}

public struct RunReviewDesignDiffVisualFocus: Sendable, Hashable {
    public let kind: String
    public let title: String
    public let subtitle: String?
    public let emphasis: String
    public let changedFields: [String]

    public init(
        kind: String,
        title: String,
        subtitle: String? = nil,
        emphasis: String,
        changedFields: [String] = []
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.emphasis = emphasis
        self.changedFields = changedFields
    }
}

public struct RunReviewDesignDiffValueChangeSummary: Sendable, Hashable {
    public let path: String
    public let state: String
    public let beforePreview: String?
    public let afterPreview: String?

    public init(
        path: String,
        state: String,
        beforePreview: String? = nil,
        afterPreview: String? = nil
    ) {
        self.path = path
        self.state = state
        self.beforePreview = beforePreview
        self.afterPreview = afterPreview
    }
}
