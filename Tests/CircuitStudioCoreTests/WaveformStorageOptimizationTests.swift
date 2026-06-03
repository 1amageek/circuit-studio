import Foundation
import Testing
import CoreSpice
import CoreSpiceWaveform
@testable import CircuitStudioCore

@Suite("Waveform Storage Optimization Tests")
struct WaveformStorageOptimizationTests {

    @Test(.timeLimit(.minutes(1)))
    func transientBuilderProducesRowMajorWaveform() {
        var builder = TransientWaveformBuilder(
            variableMap: [
                .nodeVoltage(Node(id: 1)): 0,
                .nodeVoltage(Node(id: 2)): 1,
            ],
            nodeNamesByID: [
                1: "in",
                2: "out",
            ]
        )

        builder.appendBatch(
            timePoints: [0.0, 1.0],
            rowMajorSolutions: [0.1, 1.1, 0.2, 1.2],
            sourceVariableCount: 2
        )

        let waveform = builder.buildWaveformData()
        let values = waveform.withRealRowMajorBuffer { buffer in
            (0..<buffer.pointCount).flatMap { point in
                (0..<buffer.variableCount).map { variable in
                    buffer.value(point: point, variable: variable) ?? .nan
                }
            }
        }

        #expect(waveform.sweepValues == [0.0, 1.0])
        #expect(waveform.variables.map(\.name) == ["V(in)", "V(out)"])
        #expect(values == [0.1, 1.1, 0.2, 1.2])
    }

    @Test(.timeLimit(.minutes(1)))
    func ngspiceRawParserProducesRowMajorWaveform() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioWaveformStorage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove temporary root: \(error)")
            }
        }

        let rawURL = root.appending(path: "simulation.raw")
        try """
        Title: row major test
        Plotname: Transient Analysis
        Flags: real
        No. Variables: 3
        No. Points: 2
        Variables:
            0 time time
            1 v(out) voltage
            2 i(v1) current
        Values:
            0 0.0
                1.0
                0.1
            1 1.0
                2.0
                0.2
        """.write(to: rawURL, atomically: true, encoding: .utf8)

        let waveform = try NgspiceRawParser().parse(rawURL: rawURL, fallbackAnalysis: nil)
        let values = waveform.withRealRowMajorBuffer { buffer in
            (0..<buffer.pointCount).flatMap { point in
                (0..<buffer.variableCount).map { variable in
                    buffer.value(point: point, variable: variable) ?? .nan
                }
            }
        }

        #expect(waveform.sweepValues == [0.0, 1.0])
        #expect(waveform.variables.map(\.name) == ["v(out)", "i(v1)"])
        #expect(values == [1.0, 0.1, 2.0, 0.2])
    }

    @Test(.timeLimit(.minutes(1)))
    func waveformServiceKeepsDecimatedWaveformRowMajor() {
        let waveform = WaveformData(
            metadata: SimulationMetadata(
                title: "Decimation",
                analysisType: .transient,
                pointCount: 10,
                variableCount: 2
            ),
            sweepVariable: .time(),
            sweepValues: Array(0..<10).map(Double.init),
            variables: [
                .voltage(node: "out", index: 0),
                .current(device: "V1", index: 1),
            ],
            realRowMajorData: [
                0.0, 0.0,
                1.0, 0.1,
                2.0, 0.2,
                3.0, 0.3,
                4.0, 0.4,
                5.0, 0.5,
                6.0, 0.6,
                7.0, 0.7,
                8.0, 0.8,
                9.0, 0.9,
            ],
            pointCount: 10,
            variableCount: 2
        )

        let decimated = WaveformService().fetch(
            waveform: waveform,
            variables: [],
            range: nil,
            maxPoints: 4
        )
        let values = decimated.withRealRowMajorBuffer { buffer in
            (0..<buffer.pointCount).flatMap { point in
                (0..<buffer.variableCount).map { variable in
                    buffer.value(point: point, variable: variable) ?? .nan
                }
            }
        }

        #expect(decimated.sweepValues == [0.0, 5.0, 6.0, 9.0])
        #expect(values == [0.0, 0.0, 5.0, 0.5, 6.0, 0.6, 9.0, 0.9])
    }

    @Test(.timeLimit(.minutes(1)))
    func waveformServiceReturnsRowMajorSliceWhenRangeNeedsNoDecimation() {
        let waveform = WaveformData(
            metadata: SimulationMetadata(
                title: "Slice",
                analysisType: .transient,
                pointCount: 10,
                variableCount: 1
            ),
            sweepVariable: .time(),
            sweepValues: Array(0..<10).map(Double.init),
            variables: [
                .voltage(node: "out", index: 0),
            ],
            realRowMajorData: Array(0..<10).map(Double.init),
            pointCount: 10,
            variableCount: 1
        )

        let sliced = WaveformService().fetch(
            waveform: waveform,
            variables: [],
            range: 2.0...4.0,
            maxPoints: 4
        )
        let values = sliced.withRealRowMajorBuffer { buffer in
            (0..<buffer.pointCount).compactMap { point in
                buffer.value(point: point, variable: 0)
            }
        }

        #expect(sliced.sweepValues == [2.0, 3.0, 4.0])
        #expect(values == [2.0, 3.0, 4.0])
    }
}
