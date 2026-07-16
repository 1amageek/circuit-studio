import Foundation

/// Executes every analysis × corner cell of a request sequentially and
/// returns one record per cell.
///
/// A failed cell records its reason and the matrix continues; a cancelled
/// cell stops the matrix and marks every remaining cell cancelled, so the
/// batch always accounts for the whole matrix.
public struct AnalysisMatrixRunner: Sendable {
    private let simulationService: any SimulationRunning

    public init(simulationService: any SimulationRunning) {
        self.simulationService = simulationService
    }

    public func run(
        _ request: AnalysisMatrixRequest,
        onRecordFinished: (@Sendable (AnalysisRunRecord) -> Void)? = nil
    ) async -> [AnalysisRunRecord] {
        var records: [AnalysisRunRecord] = []
        var remaining = cells(for: request)[...]

        while let cell = remaining.first {
            remaining = remaining.dropFirst()
            let configuration = cellConfiguration(
                base: request.baseConfiguration,
                corner: cell.corner
            )
            let startedAt = Date()

            do {
                let result = try await simulationService.runAnalysis(
                    source: request.source,
                    fileName: request.fileName,
                    processConfiguration: configuration,
                    command: cell.analysis
                )
                let record = AnalysisRunRecord(
                    analysis: cell.analysis,
                    cornerName: cell.corner?.name,
                    temperature: resolvedTemperature(for: configuration),
                    status: .completed,
                    result: result,
                    startedAt: startedAt,
                    finishedAt: Date()
                )
                records.append(record)
                onRecordFinished?(record)
            } catch let error as StudioError where error == .cancelled {
                let record = AnalysisRunRecord(
                    analysis: cell.analysis,
                    cornerName: cell.corner?.name,
                    temperature: resolvedTemperature(for: configuration),
                    status: .cancelled,
                    failureReason: error.localizedDescription,
                    startedAt: startedAt,
                    finishedAt: Date()
                )
                records.append(record)
                onRecordFinished?(record)

                while let leftover = remaining.first {
                    remaining = remaining.dropFirst()
                    let leftoverConfiguration = cellConfiguration(
                        base: request.baseConfiguration,
                        corner: leftover.corner
                    )
                    let skipped = AnalysisRunRecord(
                        analysis: leftover.analysis,
                        cornerName: leftover.corner?.name,
                        temperature: resolvedTemperature(for: leftoverConfiguration),
                        status: .cancelled,
                        failureReason: "Cancelled before start",
                        startedAt: Date(),
                        finishedAt: Date()
                    )
                    records.append(skipped)
                    onRecordFinished?(skipped)
                }
                break
            } catch {
                let record = AnalysisRunRecord(
                    analysis: cell.analysis,
                    cornerName: cell.corner?.name,
                    temperature: resolvedTemperature(for: configuration),
                    status: .failed,
                    failureReason: error.localizedDescription,
                    startedAt: startedAt,
                    finishedAt: Date()
                )
                records.append(record)
                onRecordFinished?(record)
            }
        }

        return records
    }

    // MARK: - Cell Expansion

    private struct Cell {
        let analysis: AnalysisCommand
        let corner: Corner?
    }

    /// Analysis-major expansion: every corner of one analysis runs before the
    /// next analysis starts, so corner comparisons finish as early as possible.
    private func cells(for request: AnalysisMatrixRequest) -> [Cell] {
        guard !request.corners.isEmpty else {
            return request.analyses.map { Cell(analysis: $0, corner: nil) }
        }
        var cells: [Cell] = []
        cells.reserveCapacity(request.analyses.count * request.corners.count)
        for analysis in request.analyses {
            for corner in request.corners {
                cells.append(Cell(analysis: analysis, corner: corner))
            }
        }
        return cells
    }

    private func cellConfiguration(
        base: ProcessConfiguration?,
        corner: Corner?
    ) -> ProcessConfiguration? {
        guard let corner else { return base }
        return (base ?? ProcessConfiguration()).selecting(corner: corner)
    }

    /// The temperature the configuration dictates, or nil when nothing does.
    /// No default is fabricated here: nil means the simulator's own
    /// resolution (netlist `.temp` card or engine default) decides.
    private func resolvedTemperature(for configuration: ProcessConfiguration?) -> Double? {
        guard let configuration else { return nil }
        return configuration.temperatureOverride
            ?? configuration.effectiveCorner()?.temperature
            ?? configuration.technology?.defaultTemperature
    }
}
