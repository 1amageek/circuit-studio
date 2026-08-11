import DRCAdapters
import DRCCore
import Foundation
import LVSAdapters
import LVSCore
import LVSExtractionAdapters

/// Projects canonical DRCEngine and LVSEngine results into the application review model.
///
/// `locate()` returns nil when the toolchain is unavailable; callers that require
/// live signoff must treat nil as a hard error (no silent fallback to mock/replay).
public struct LiveSignoffService: Sendable {

    private let drc: any DRCBackend
    private let lvs: any LVSBackend
    private let extractor: any LVSLayoutNetlistExtracting

    public init(
        drc: any DRCBackend,
        lvs: any LVSBackend,
        extractor: any LVSLayoutNetlistExtracting
    ) {
        self.drc = drc
        self.lvs = lvs
        self.extractor = extractor
    }

    /// Discovers the full DRC+LVS toolchain (Magic + Netgen + profile-resolved PDK). Returns
    /// nil if any piece is missing — the caller decides how to handle that.
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> LiveSignoffService? {
        guard let drc = MagicDRCAdapter.locate(environment: environment, fileManager: fileManager),
              let lvs = NetgenLVSAdapter.locate(environment: environment, fileManager: fileManager),
              let extractor = MagicLayoutNetlistExtractor.locate(
                  environment: environment,
                  fileManager: fileManager
              ) else {
            return nil
        }
        return LiveSignoffService(drc: drc, lvs: lvs, extractor: extractor)
    }

    /// Runs DRC then LVS on `layoutGDS` (top cell `topCell`) against
    /// `schematicNetlist`, returning a review whose `passed` is true only when
    /// both the DRC and LVS reports pass.
    public func run(
        layoutGDS: URL,
        topCell: String,
        schematicNetlist: URL,
        artifactDirectory: URL
    ) async throws -> ExternalSignoffReview {
        try await execute(
            layoutGDS: layoutGDS,
            topCell: topCell,
            schematicNetlist: schematicNetlist,
            artifactDirectory: artifactDirectory
        ).review
    }

    /// Executes both canonical engines and retains their typed results so callers
    /// can persist exact tool provenance and engine-owned summary projections.
    public func execute(
        layoutGDS: URL,
        topCell: String,
        schematicNetlist: URL,
        artifactDirectory: URL
    ) async throws -> LiveSignoffExecutionResult {
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

        let drcExecution = try await drc.run(
            DRCRequest(
                layoutURL: layoutGDS,
                topCell: topCell,
                layoutFormat: .gds,
                workingDirectory: artifactDirectory,
                backendSelection: DRCBackendSelection(backendID: drc.backendID)
            )
        )

        let layoutNetlist = try await extractor.extractLayoutNetlist(
            gds: layoutGDS,
            topCell: topCell,
            into: artifactDirectory,
            timeoutSeconds: 300
        )

        let lvsExecution = try await lvs.run(
            LVSRequest(
                layoutNetlistURL: try layoutNetlist.netlistFileURL(),
                schematicNetlistURL: schematicNetlist,
                topCell: topCell,
                workingDirectory: artifactDirectory,
                backendSelection: LVSBackendSelection(backendID: lvs.backendID),
                executionInputBindings: [layoutNetlist.netlist]
            )
        )

        let review = ExternalSignoffReview(
            reports: [
                ExternalSignoffToolReport(drcResult: drcExecution.result),
                ExternalSignoffToolReport(lvsResult: lvsExecution.result),
            ]
        )
        return LiveSignoffExecutionResult(
            drc: drcExecution,
            lvs: lvsExecution,
            review: review
        )
    }
}
