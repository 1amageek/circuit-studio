import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor
import LayoutEditor

/// Regression tests for generating a layout while the layout editor is not
/// yet on screen (Layout-workspace empty state). The fit must not be lost
/// when the canvas has no size at generation time.
@Suite("Generate Layout Viewport Tests")
@MainActor
struct GenerateLayoutViewportTests {

    @Test func generateBeforeCanvasIsSizedFitsWhenCanvasAppears() throws {
        let project = StudioSession(
            schematicViewModel: SchematicPreview.cmosInverterViewModel()
        )
        let catalog = DeviceCatalog.standard()
        let service = DesignFlowService(netlistGenerator: NetlistGenerator(catalog: catalog))
        #expect(project.layoutViewModel.canvasSize == .zero)

        // The empty-state button generates while the editor view is off
        // screen, so the canvas still reports zero size.
        project.generateLayout(service: service, catalog: catalog)

        #expect(project.layoutGenerationError == nil)
        #expect(project.designUnit != nil)

        // The active cell must resolve inside the generated document — a
        // stale activeCellID from the pre-generation document draws nothing.
        let activeCell = try #require(project.layoutViewModel.activeCell)
        #expect(activeCell.id == project.layoutViewModel.editor.document.topCellID)
        #expect(!activeCell.shapes.isEmpty || !activeCell.instances.isEmpty)

        // The editor view appears and its GeometryReader reports the size.
        project.layoutViewModel.canvasSize = CGSize(width: 1200, height: 800)

        // The deferred fit must match an explicit fitAll at this size.
        let zoomAfterSizing = project.layoutViewModel.zoom
        let offsetAfterSizing = project.layoutViewModel.offset
        project.layoutViewModel.fitAll()
        #expect(zoomAfterSizing == project.layoutViewModel.zoom)
        #expect(offsetAfterSizing == project.layoutViewModel.offset)

        // And it must actually have moved the viewport off the defaults —
        // generated cells live at DBU scale, far outside a 1:1 view.
        #expect(zoomAfterSizing != 1.0)
        #expect(offsetAfterSizing != .zero)
    }

    @Test func canvasResizeAfterDeferredFitDoesNotRefitAgain() throws {
        let project = StudioSession(
            schematicViewModel: SchematicPreview.cmosInverterViewModel()
        )
        let catalog = DeviceCatalog.standard()
        let service = DesignFlowService(netlistGenerator: NetlistGenerator(catalog: catalog))
        project.generateLayout(service: service, catalog: catalog)
        project.layoutViewModel.canvasSize = CGSize(width: 1200, height: 800)

        // Simulate a manual zoom after the deferred fit ran.
        project.layoutViewModel.zoom = 3.0
        project.layoutViewModel.offset = CGPoint(x: 10, y: 10)

        // A later window resize must not clobber the user's viewport.
        project.layoutViewModel.canvasSize = CGSize(width: 900, height: 600)
        #expect(project.layoutViewModel.zoom == 3.0)
        #expect(project.layoutViewModel.offset == CGPoint(x: 10, y: 10))
    }
}
