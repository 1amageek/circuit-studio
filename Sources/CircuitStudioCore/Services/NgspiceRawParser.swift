import Foundation
import CoreSpiceWaveform

/// Parses ngspice ASCII RAW output into WaveformData.
public struct NgspiceRawParser: Sendable {
    public init() {}

    public func parse(rawURL: URL, fallbackAnalysis: AnalysisCommand?) throws -> WaveformData {
        let text = try String(contentsOf: rawURL, encoding: .utf8)
        let lines = text.split(whereSeparator: \.isNewline).map { String($0) }

        var header: [String: String] = [:]
        var variables: [RawVariable] = []
        var valueTokens: [String] = []
        var inVariables = false
        var inValues = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.lowercased().hasPrefix("variables:") {
                inVariables = true
                inValues = false
                continue
            }
            if trimmed.lowercased().hasPrefix("values:") {
                inVariables = false
                inValues = true
                continue
            }

            if inVariables {
                let parts = trimmed.split(whereSeparator: \.isWhitespace).map { String($0) }
                guard parts.count >= 3, let index = Int(parts[0]) else { continue }
                variables.append(RawVariable(
                    index: index,
                    name: parts[1],
                    type: parts[2]
                ))
                continue
            }

            if inValues {
                valueTokens.append(contentsOf: trimmed.split(whereSeparator: \.isWhitespace).map { String($0) })
                continue
            }

            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = trimmed[..<colonIndex].trimmingCharacters(in: .whitespaces)
                let value = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                header[key] = value
            }
        }

        let pointCount = Int(header["No. Points"] ?? "") ?? 0
        let variableCount = Int(header["No. Variables"] ?? "") ?? variables.count
        let flags = header["Flags"]?.lowercased() ?? ""
        let isComplex = flags.contains("complex")

        guard variableCount > 0, pointCount > 0 else {
            throw StudioError.simulationFailure("Invalid RAW output: missing points or variables")
        }

        if variables.isEmpty {
            throw StudioError.simulationFailure("Invalid RAW output: no variables found")
        }

        let parsed = try parseValues(
            tokens: valueTokens,
            pointCount: pointCount,
            variableCount: variableCount,
            isComplex: isComplex
        )

        let sweepVariable = makeSweepVariable(from: variables.first?.name ?? "time")
        let dataVariables = variables.dropFirst()
        let descriptors = dataVariables.enumerated().map { index, variable in
            makeVariableDescriptor(from: variable.name, index: index)
        }

        let analysisType = analysisKind(
            plotName: header["Plotname"],
            fallback: fallbackAnalysis
        )

        let metadata = SimulationMetadata(
            title: header["Title"],
            tool: "ngspice",
            analysisType: analysisType,
            pointCount: pointCount,
            variableCount: descriptors.count,
            isComplex: isComplex
        )

        if isComplex {
            return WaveformData(
                metadata: metadata,
                sweepVariable: sweepVariable,
                sweepValues: parsed.sweepValues,
                variables: descriptors,
                complexData: parsed.complexData
            )
        }

        return WaveformData(
            metadata: metadata,
            sweepVariable: sweepVariable,
            sweepValues: parsed.sweepValues,
            variables: descriptors,
            realData: parsed.realData
        )
    }

    private func parseValues(
        tokens: [String],
        pointCount: Int,
        variableCount: Int,
        isComplex: Bool
    ) throws -> ParsedValues {
        var index = 0
        var sweepValues: [Double] = []
        sweepValues.reserveCapacity(pointCount)

        var realData: [[Double]] = Array(repeating: [], count: pointCount)
        var complexData: [[(real: Double, imag: Double)]] = Array(repeating: [], count: pointCount)

        for point in 0..<pointCount {
            guard index < tokens.count else {
                throw StudioError.simulationFailure("RAW output truncated at point \(point)")
            }
            index += 1 // skip point index

            var pointSweep: Double = 0
            var realRow: [Double] = []
            var complexRow: [(real: Double, imag: Double)] = []
            realRow.reserveCapacity(max(variableCount - 1, 0))
            complexRow.reserveCapacity(max(variableCount - 1, 0))

            for varIndex in 0..<variableCount {
                guard index < tokens.count else {
                    throw StudioError.simulationFailure("RAW output truncated at variable \(varIndex)")
                }

                let token = tokens[index]
                index += 1

                if isComplex {
                    let (real, imag, consumedExtra) = parseComplexToken(
                        token,
                        nextToken: index < tokens.count ? tokens[index] : nil
                    )
                    if consumedExtra { index += 1 }

                    if varIndex == 0 {
                        pointSweep = real
                    } else {
                        complexRow.append((real: real, imag: imag))
                    }
                } else {
                    guard let value = Double(token) else {
                        throw StudioError.simulationFailure("Invalid numeric value in RAW output: \(token)")
                    }
                    if varIndex == 0 {
                        pointSweep = value
                    } else {
                        realRow.append(value)
                    }
                }
            }

            sweepValues.append(pointSweep)
            if isComplex {
                complexData[point] = complexRow
            } else {
                realData[point] = realRow
            }
        }

        return ParsedValues(
            sweepValues: sweepValues,
            realData: realData,
            complexData: complexData
        )
    }

    private func parseComplexToken(_ token: String, nextToken: String?) -> (Double, Double, Bool) {
        if let commaIndex = token.firstIndex(of: ",") {
            let realPart = String(token[..<commaIndex])
            let imagPart = String(token[token.index(after: commaIndex)...])
            return (Double(realPart) ?? 0, Double(imagPart) ?? 0, false)
        }

        let real = Double(token) ?? 0
        let imag = nextToken.flatMap(Double.init) ?? 0
        return (real, imag, true)
    }

    private func makeSweepVariable(from name: String) -> VariableDescriptor {
        let lower = name.lowercased()
        if lower.contains("frequency") {
            return .frequency()
        }
        if lower.contains("time") {
            return .time()
        }
        return VariableDescriptor(
            name: name,
            unit: .dimensionless,
            type: .parameter,
            index: 0
        )
    }

    private func makeVariableDescriptor(from name: String, index: Int) -> VariableDescriptor {
        let lower = name.lowercased()
        if lower.hasPrefix("v(") {
            return VariableDescriptor(name: name, unit: .volt, type: .voltage, index: index)
        }
        if lower.hasPrefix("i(") {
            return VariableDescriptor(name: name, unit: .ampere, type: .current, index: index)
        }
        if lower.contains("frequency") {
            return VariableDescriptor(name: name, unit: .hertz, type: .frequency, index: index)
        }
        if lower.contains("time") {
            return VariableDescriptor(name: name, unit: .second, type: .time, index: index)
        }
        return VariableDescriptor(name: name, unit: .dimensionless, type: .parameter, index: index)
    }

    private func analysisKind(plotName: String?, fallback: AnalysisCommand?) -> AnalysisKind {
        if let fallback {
            switch fallback {
            case .op: return .op
            case .tran: return .tran
            case .ac: return .ac
            case .dcSweep: return .dc
            case .noise: return .noise
            case .tf: return .tf
            case .pz: return .pz
            }
        }

        let lower = plotName?.lowercased() ?? ""
        if lower.contains("ac") { return .ac }
        if lower.contains("tran") || lower.contains("transient") { return .tran }
        if lower.contains("dc") { return .dc }
        if lower.contains("noise") { return .noise }
        if lower.contains("transfer") { return .tf }
        if lower.contains("pole") { return .pz }
        return .op
    }

    private struct RawVariable: Sendable {
        let index: Int
        let name: String
        let type: String
    }

    private struct ParsedValues: Sendable {
        let sweepValues: [Double]
        let realData: [[Double]]
        let complexData: [[(real: Double, imag: Double)]]
    }
}
