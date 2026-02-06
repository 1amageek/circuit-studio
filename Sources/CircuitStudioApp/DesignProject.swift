import SwiftUI
import CircuitStudioCore
import SchematicEditor
import WaveformViewer
import LayoutEditor

/// Unified design project that owns all editor ViewModels and shared state.
@Observable
@MainActor
public final class DesignProject {
    // Editor ViewModels
    public let schematicViewModel: SchematicViewModel
    public let layoutViewModel: LayoutEditorViewModel
    public let waveformViewModel: WaveformViewModel

    // Cross-probe
    public let crossProbe: CrossProbeService

    // Design metadata
    public var designName: String = "Untitled"
    public var isNetlistDirty: Bool = false

    public init(
        schematicViewModel: SchematicViewModel = SchematicViewModel(),
        layoutViewModel: LayoutEditorViewModel = LayoutEditorViewModel(),
        waveformViewModel: WaveformViewModel = WaveformViewModel()
    ) {
        self.schematicViewModel = schematicViewModel
        self.layoutViewModel = layoutViewModel
        self.waveformViewModel = waveformViewModel
        self.crossProbe = CrossProbeService()
    }
}
