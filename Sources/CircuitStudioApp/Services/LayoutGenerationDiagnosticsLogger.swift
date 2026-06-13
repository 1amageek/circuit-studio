import Foundation
import OSLog
import CircuitStudioCore

enum LayoutGenerationDiagnosticsLogger {
    private static let logger = Logger(
        subsystem: "CircuitStudio",
        category: "LayoutGeneration"
    )

    @MainActor
    static func log(report: LayoutGenerationPreflightReport) {
        let message = report.diagnosticMessage()
        let json = report.jsonMessage()

        if report.availability.isAvailable {
            logger.info("\(message, privacy: .public); report=\(json, privacy: .public)")
        } else {
            logger.warning("\(message, privacy: .public); report=\(json, privacy: .public)")
        }
    }
}
