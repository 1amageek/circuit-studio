import Foundation
import CoreSpice
import CoreSpiceWaveform

public enum WaveformBenchmarkFixture {
    public static func waveform(
        pointCount: Int = 12_000,
        variableCount: Int = 12,
        offset: Double = 0.0
    ) -> WaveformData {
        let sweepValues = (0..<pointCount).map { Double($0) * 1.0e-9 }
        let variables = (0..<variableCount).map { index in
            VariableDescriptor.voltage(node: "n\(index)", index: index)
        }
        var values: [Double] = []
        values.reserveCapacity(pointCount * variableCount)
        for point in 0..<pointCount {
            for variable in 0..<variableCount {
                let sample = sin(Double(point) * 0.004 + Double(variable) * 0.2)
                    + cos(Double(point) * 0.001 + Double(variable) * 0.05)
                    + offset
                values.append(sample)
            }
        }
        return WaveformData(
            metadata: SimulationMetadata(
                title: "Benchmark",
                analysisType: .transient,
                pointCount: pointCount,
                variableCount: variableCount
            ),
            sweepVariable: .time(),
            sweepValues: sweepValues,
            variables: variables,
            realRowMajorData: values,
            pointCount: pointCount,
            variableCount: variableCount
        )
    }

    public static func nestedWaveform(
        pointCount: Int = 12_000,
        variableCount: Int = 12,
        offset: Double = 0.0
    ) -> WaveformData {
        let sweepValues = (0..<pointCount).map { Double($0) * 1.0e-9 }
        let variables = (0..<variableCount).map { index in
            VariableDescriptor.voltage(node: "n\(index)", index: index)
        }
        var rows: [[Double]] = []
        rows.reserveCapacity(pointCount)
        for point in 0..<pointCount {
            var row: [Double] = []
            row.reserveCapacity(variableCount)
            for variable in 0..<variableCount {
                let sample = sin(Double(point) * 0.004 + Double(variable) * 0.2)
                    + cos(Double(point) * 0.001 + Double(variable) * 0.05)
                    + offset
                row.append(sample)
            }
            rows.append(row)
        }
        return WaveformData(
            metadata: SimulationMetadata(
                title: "Benchmark",
                analysisType: .transient,
                pointCount: pointCount,
                variableCount: variableCount
            ),
            sweepVariable: .time(),
            sweepValues: sweepValues,
            variables: variables,
            realData: rows
        )
    }

    public static func transientVariableMap(variableCount: Int) -> [MNAVariable: Int] {
        Dictionary(uniqueKeysWithValues: (0..<variableCount).map { index in
            (MNAVariable.nodeVoltage(Node(id: index + 1)), index)
        })
    }

    public static func nodeNamesByID(variableCount: Int) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: (0..<variableCount).map { index in
            (index + 1, "n\(index)")
        })
    }

    public static func rowMajorSolutions(pointCount: Int, variableCount: Int) -> [Double] {
        var values: [Double] = []
        values.reserveCapacity(pointCount * variableCount)
        for point in 0..<pointCount {
            for variable in 0..<variableCount {
                values.append(Double(point) * 0.001 + Double(variable) * 0.01)
            }
        }
        return values
    }

    public static func rawFile(pointCount: Int, variableCount: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioBenchmarks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "waveform.raw")

        var text = """
        Title: benchmark
        Plotname: Transient Analysis
        Flags: real
        No. Variables: \(variableCount + 1)
        No. Points: \(pointCount)
        Variables:
            0 time time
        """
        for variable in 0..<variableCount {
            text += "\n    \(variable + 1) v(n\(variable)) voltage"
        }
        text += "\nValues:\n"
        for point in 0..<pointCount {
            text += "    \(point) \(Double(point) * 1.0e-9)\n"
            for variable in 0..<variableCount {
                let sample = sin(Double(point) * 0.004 + Double(variable) * 0.2)
                text += "        \(sample)\n"
            }
        }

        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
