import CoreSpiceWaveform
import Foundation
import Testing

@testable import CircuitStudioCore

@Suite("Corner Overlay Builder Tests")
struct CornerOverlayBuilderTests {

    @Test("Traces are renamed with their corner label")
    func tracesAreRenamedWithCornerLabel() throws {
        let overlay = try CornerOverlayBuilder().build(sources: [
            .init(label: "tt", waveform: transientWaveform(sweep: [0, 1, 2], values: [0, 1, 2])),
            .init(label: "ff", waveform: transientWaveform(sweep: [0, 1, 2], values: [0, 2, 4])),
        ])

        #expect(overlay.variables.map(\.name) == ["V(out) [tt]", "V(out) [ff]"])
        #expect(overlay.metadata.analysisType == .transient)
        #expect(overlay.metadata.isComplex == false)
        #expect(overlay.variables.map(\.index) == [0, 1])
    }

    @Test("Sparse sources are resampled onto the densest sweep axis")
    func sparseSourcesAreResampledOntoDensestAxis() throws {
        let dense = transientWaveform(sweep: [0, 1, 2, 3, 4], values: [0, 2, 4, 6, 8])
        let sparse = transientWaveform(sweep: [0, 4], values: [0, 8])

        let overlay = try CornerOverlayBuilder().build(sources: [
            .init(label: "tt", waveform: dense),
            .init(label: "ss", waveform: sparse),
        ])

        #expect(overlay.pointCount == 5)
        #expect(overlay.sweepValues == [0, 1, 2, 3, 4])
        let resampled = try (0..<5).map { point in
            try #require(overlay.realValue(variable: 1, point: point))
        }
        for (value, expected) in zip(resampled, [0.0, 2.0, 4.0, 6.0, 8.0]) {
            #expect(abs(value - expected) < 1e-12)
        }
    }

    @Test("Complex AC waveforms merge into a complex overlay")
    func complexACWaveformsMergeIntoComplexOverlay() throws {
        let overlay = try CornerOverlayBuilder().build(sources: [
            .init(label: "tt", waveform: acWaveform(
                sweep: [1, 10, 100],
                values: [(1, 0), (0.5, -0.5), (0.1, -0.2)]
            )),
            .init(label: "ss", waveform: acWaveform(
                sweep: [1, 10, 100],
                values: [(0.9, 0), (0.4, -0.4), (0.05, -0.1)]
            )),
        ])

        #expect(overlay.metadata.isComplex)
        #expect(overlay.variables.map(\.name) == ["V(out) [tt]", "V(out) [ss]"])
        let value = try #require(overlay.complexValue(variable: 1, point: 1))
        #expect(abs(value.real - 0.4) < 1e-12)
        #expect(abs(value.imag - (-0.4)) < 1e-12)
    }

    @Test("Fewer than two sources are rejected")
    func fewerThanTwoSourcesAreRejected() {
        let source = CornerOverlayBuilder.Source(
            label: "tt",
            waveform: transientWaveform(sweep: [0, 1], values: [0, 1])
        )
        #expect(throws: CornerOverlayBuilder.OverlayError.insufficientSources(count: 1)) {
            try CornerOverlayBuilder().build(sources: [source])
        }
    }

    @Test("Mixed analysis domains are rejected")
    func mixedAnalysisDomainsAreRejected() {
        #expect(throws: CornerOverlayBuilder.OverlayError.mixedDomains) {
            try CornerOverlayBuilder().build(sources: [
                .init(label: "tt", waveform: transientWaveform(sweep: [0, 1], values: [0, 1])),
                .init(label: "ss", waveform: acWaveform(sweep: [1, 10], values: [(1, 0), (0.5, 0)])),
            ])
        }
    }

    @Test("Pole-zero results are rejected: their sweep is an index, not an axis")
    func poleZeroResultsAreRejected() {
        let poleZero = WaveformData(
            metadata: SimulationMetadata(analysisType: .poleZero, pointCount: 2, variableCount: 1),
            sweepVariable: VariableDescriptor(name: "index", unit: .dimensionless, type: .parameter, index: 0),
            sweepValues: [0, 1],
            variables: [.voltage(node: "pole", index: 0)],
            complexData: [[(real: -1.0, imag: 0.5)], [(real: -2.0, imag: -0.5)]]
        )
        #expect(throws: CornerOverlayBuilder.OverlayError.unsupportedAnalysis(.poleZero)) {
            try CornerOverlayBuilder().build(sources: [
                .init(label: "tt", waveform: poleZero),
                .init(label: "ss", waveform: poleZero),
            ])
        }
    }

    @Test("Empty sweeps are rejected")
    func emptySweepsAreRejected() {
        #expect(throws: CornerOverlayBuilder.OverlayError.emptySweep) {
            try CornerOverlayBuilder().build(sources: [
                .init(label: "tt", waveform: transientWaveform(sweep: [0, 1], values: [0, 1])),
                .init(label: "ss", waveform: transientWaveform(sweep: [], values: [])),
            ])
        }
    }

    // MARK: - Fixtures

    private func transientWaveform(sweep: [Double], values: [Double]) -> WaveformData {
        WaveformData(
            metadata: SimulationMetadata(
                analysisType: .transient,
                pointCount: sweep.count,
                variableCount: 1
            ),
            sweepVariable: .time(index: 0),
            sweepValues: sweep,
            variables: [.voltage(node: "out", index: 0)],
            realData: values.map { [$0] }
        )
    }

    private func acWaveform(
        sweep: [Double],
        values: [(real: Double, imag: Double)]
    ) -> WaveformData {
        WaveformData(
            metadata: SimulationMetadata(
                analysisType: .ac,
                pointCount: sweep.count,
                variableCount: 1,
                isComplex: true
            ),
            sweepVariable: .frequency(index: 0),
            sweepValues: sweep,
            variables: [.voltage(node: "out", index: 0)],
            complexData: values.map { [$0] }
        )
    }
}
