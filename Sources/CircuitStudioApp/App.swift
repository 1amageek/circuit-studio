import SwiftUI
import CircuitStudioCore
import WaveformViewer
import SchematicEditor

public struct CircuitStudioApp: App {
    @State private var appState = AppState()
    @State private var services = ServiceContainer()
    @State private var waveformViewModel = WaveformViewModel()
    @State private var schematicViewModel = SchematicViewModel()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView(
                appState: appState,
                services: services,
                waveformViewModel: waveformViewModel,
                schematicViewModel: schematicViewModel
            )
            .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1200, height: 700)
    }
}
