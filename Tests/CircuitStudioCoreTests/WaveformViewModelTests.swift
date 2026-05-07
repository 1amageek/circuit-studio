import Foundation
import Testing
import CoreSpiceWaveform
@testable import CircuitStudioCore
@testable import WaveformViewer

@MainActor
@Suite("WaveformViewModel Tests")
struct WaveformViewModelTests {

    @Test func loadCreatesVisibleTracesAndChartSeries() {
        let viewModel = WaveformViewModel()
        let waveform = makeTransientWaveform()

        viewModel.load(waveform: waveform)

        #expect(viewModel.sweepLabel == "time")
        #expect(!viewModel.isComplex)
        #expect(!viewModel.isLogFrequency)
        #expect(!viewModel.isSinglePoint)
        #expect(viewModel.document.traces.map(\.variableName) == ["V(out)", "I(R1)"])
        #expect(!viewModel.document.traces.contains { !$0.isVisible })
        #expect(viewModel.document.visibleRange == 0.0...3.0)
        #expect(viewModel.chartSeries.count == 2)
        #expect(viewModel.chartSeries[0].name == "V(out)")
        #expect(viewModel.chartSeries[0].points.map(\.value) == [0.0, 1.0, 2.0, 3.0])
    }

    @Test func toggleTraceUpdatesChartSeries() {
        let viewModel = WaveformViewModel()
        viewModel.load(waveform: makeTransientWaveform())

        let firstTraceID = viewModel.document.traces[0].id
        viewModel.toggleTrace(firstTraceID)

        #expect(!viewModel.document.traces[0].isVisible)
        #expect(viewModel.chartSeries.count == 1)
        #expect(viewModel.chartSeries[0].name == "I(R1)")

        viewModel.toggleTrace(firstTraceID)

        #expect(viewModel.document.traces[0].isVisible)
        #expect(viewModel.chartSeries.count == 2)
    }

    @Test func streamingUpdatePreservesTraceVisibility() {
        let viewModel = WaveformViewModel()
        viewModel.load(waveform: makeTransientWaveform())

        let currentTraceID = viewModel.document.traces[1].id
        viewModel.toggleTrace(currentTraceID)

        viewModel.updateStreaming(waveform: makeTransientWaveform(
            sweepValues: [0, 1, 2, 3, 4],
            voltageValues: [0, 1, 2, 3, 4],
            currentValues: [0, 0.1, 0.2, 0.3, 0.4]
        ))

        #expect(viewModel.document.traces.count == 2)
        #expect(viewModel.document.traces[0].isVisible)
        #expect(!viewModel.document.traces[1].isVisible)
        #expect(viewModel.document.visibleRange == 0.0...4.0)
        #expect(viewModel.chartSeries.count == 1)
        #expect(viewModel.chartSeries[0].points.map(\.sweep) == [0, 1, 2, 3, 4])
    }

    @Test func zoomPanAndCursorUseDataBounds() {
        let viewModel = WaveformViewModel()
        viewModel.load(waveform: makeTransientWaveform())

        viewModel.setVisibleRange(1.0...2.0)
        #expect(viewModel.document.visibleRange == 1.0...2.0)
        #expect(viewModel.chartSeries[0].points.map(\.sweep) == [1.0, 2.0])

        viewModel.pan(byFraction: 10.0)
        #expect(viewModel.document.visibleRange == 2.0...3.0)

        viewModel.pan(byFraction: -10.0)
        #expect(viewModel.document.visibleRange == 0.0...1.0)

        viewModel.setCursor(at: 2.2)
        let voltage = viewModel.cursorValue(for: viewModel.document.traces[0])
        #expect(voltage == 2.0)

        viewModel.resetZoom()
        #expect(viewModel.document.visibleRange == 0.0...3.0)
        #expect(viewModel.zoomLevel == 0)
    }

    @Test func complexFrequencyWaveformUsesMagnitudeDB() {
        let viewModel = WaveformViewModel()
        viewModel.load(waveform: makeACWaveform())

        #expect(viewModel.isComplex)
        #expect(viewModel.isLogFrequency)
        #expect(viewModel.sweepLabel == "frequency")
        #expect(viewModel.chartSeries.count == 1)

        let values = viewModel.chartSeries[0].points.map(\.value)
        #expect(abs(values[0] - 0.0) < 1e-12)
        #expect(abs(values[1] - 6.020599913279624) < 1e-9)

        viewModel.setCursor(at: 900.0)
        let magnitude = viewModel.cursorValue(for: viewModel.document.traces[0])
        #expect(magnitude == 2.0)
    }

    @Test func applyTerminalComponentsFiltersAvailableVariables() {
        let viewModel = WaveformViewModel()
        viewModel.load(waveform: makeTransientWaveform())

        viewModel.applyTerminalComponents([
            ResolvedTerminal(componentID: UUID(), label: "OUT", variableName: "V(out)"),
            ResolvedTerminal(componentID: UUID(), label: "MISSING", variableName: "V(missing)"),
        ])

        #expect(viewModel.document.traces.count == 1)
        #expect(viewModel.document.traces[0].displayName == "OUT")
        #expect(viewModel.document.traces[0].variableName == "V(out)")
        #expect(viewModel.chartSeries.count == 1)
        #expect(viewModel.chartSeries[0].name == "OUT")
    }

    private func makeTransientWaveform(
        sweepValues: [Double] = [0, 1, 2, 3],
        voltageValues: [Double] = [0, 1, 2, 3],
        currentValues: [Double] = [0, 0.1, 0.2, 0.3]
    ) -> WaveformData {
        WaveformData(
            metadata: SimulationMetadata(
                title: "Transient",
                analysisType: .transient,
                pointCount: sweepValues.count,
                variableCount: 2
            ),
            sweepVariable: .time(),
            sweepValues: sweepValues,
            variables: [
                .voltage(node: "out", index: 0),
                .current(device: "R1", index: 1),
            ],
            realData: zip(voltageValues, currentValues).map { [$0.0, $0.1] }
        )
    }

    private func makeACWaveform() -> WaveformData {
        WaveformData(
            metadata: SimulationMetadata(
                title: "AC",
                analysisType: .ac,
                pointCount: 2,
                variableCount: 1,
                isComplex: true
            ),
            sweepVariable: .frequency(),
            sweepValues: [10, 1000],
            variables: [
                .voltage(node: "out", index: 0),
            ],
            complexData: [
                [(real: 1.0, imag: 0.0)],
                [(real: 0.0, imag: 2.0)],
            ]
        )
    }
}
