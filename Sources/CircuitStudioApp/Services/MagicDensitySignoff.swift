import CircuitSignoff
import Foundation

/// The metal-density window policy: per-layer [min, max] coverage fractions. The window is
/// a CMP/foundry requirement (a layer too sparse dishes, too dense thins), kept as harness
/// policy and applied against the Magic-measured coverage — so the measurement (tool) and
/// the judgement (policy) each have one source.
public struct DensityWindow: Sendable, Hashable, Codable {
    public let minDensity: Double
    public let maxDensity: Double
    /// CIF output layer names to check (e.g. `MET1`, `MET2`).
    public let layers: [String]

    public init(minDensity: Double = 0.35, maxDensity: Double = 0.85, layers: [String] = ["MET1", "MET2", "MET3", "MET4"]) {
        self.minDensity = minDensity
        self.maxDensity = maxDensity
        self.layers = layers
    }
}

/// Builds a Magic-driven metal-density signoff and parses its coverage measurement.
///
/// Magic's `cif coverage <LAYER>` reports the true GDS-derived area coverage of an output
/// layer, so the density rests on the geometry that ships. The bundled `density.tcl` runs it
/// per layer; this service parses the native "Cell Area"/"Layer Total Area" numbers into a
/// precise fraction and judges each layer against the `DensityWindow`. Locating returns nil
/// (never a mock) when Magic/PDK are absent — no silent fallback.
public struct MagicDensitySignoff: Sendable {

    public enum DensityError: Error, LocalizedError, Equatable {
        case toolFailed(exitCode: Int32, logPath: String)
        case incomplete(logPath: String)
        case noCoverage(layer: String, logPath: String)

        public var errorDescription: String? {
            switch self {
            case .toolFailed(let c, let p): return "Density driver exited \(c); see \(p)."
            case .incomplete(let p): return "Density driver did not complete (no DENSITY_DONE); see \(p)."
            case .noCoverage(let l, let p): return "Density driver produced no coverage for '\(l)'; see \(p)."
            }
        }
    }

    public let magicExecutableURL: URL
    public let rcFileURL: URL
    public let pdkRoot: String
    public let driverScriptURL: URL

    public init(magicExecutableURL: URL, rcFileURL: URL, pdkRoot: String, driverScriptURL: URL) {
        self.magicExecutableURL = magicExecutableURL
        self.rcFileURL = rcFileURL
        self.pdkRoot = pdkRoot
        self.driverScriptURL = driverScriptURL
    }

    public static var bundledDriverScriptURL: URL? {
        Bundle.module.url(forResource: "density", withExtension: "tcl")
    }

    public func command(cell: String, gds: URL?, layers: [String], artifactDirectory: URL) -> ExternalSignoffCommand {
        var environment = [
            "PDK_ROOT": pdkRoot,
            "DENSITY_CELL": cell,
            "DENSITY_LAYERS": layers.joined(separator: ","),
            "MAGTYPE": "mag",
        ]
        if let gds {
            environment["DENSITY_GDS"] = gds.path(percentEncoded: false)
        }
        return ExternalSignoffCommand(
            kind: .density,
            toolName: "magic",
            executablePath: magicExecutableURL.path(percentEncoded: false),
            arguments: [
                "-dnull", "-noconsole",
                "-rcfile", rcFileURL.path(percentEncoded: false),
                driverScriptURL.path(percentEncoded: false),
            ],
            environment: environment,
            workingDirectory: artifactDirectory,
            logFileName: "density-magic.log"
        )
    }

    /// Run the density check for `cell` against `window` and return the measured report.
    /// Throws on a tool error or an incomplete run — a failure is never a silent clean pass.
    public func run(cell: String, gds: URL?, window: DensityWindow, artifactDirectory: URL) async throws -> DensityReport {
        let command = command(cell: cell, gds: gds, layers: window.layers, artifactDirectory: artifactDirectory)
        let result = try await ExternalSignoffCommandService().run(command: command, artifactDirectory: artifactDirectory)
        let logPath = result.logURL.path(percentEncoded: false)
        let output = result.standardOutput + "\n" + result.standardError

        guard result.exitCode == 0 else { throw DensityError.toolFailed(exitCode: result.exitCode, logPath: logPath) }
        guard output.contains("DENSITY_DONE") else { throw DensityError.incomplete(logPath: logPath) }

        let coverages = try parseCoverage(output, window: window, logPath: logPath)
        return DensityReport(cell: cell, layers: coverages, completed: true, logPath: logPath)
    }

    /// Parse the per-layer `DENSITY_LAYER <L>` blocks, computing each coverage as
    /// `Layer Total Area / Cell Area` from Magic's native numbers (more precise than the
    /// rounded "Coverage in cell = X%" line). A requested layer with no coverage block is a
    /// driver failure, not a 0%-pass.
    private func parseCoverage(_ output: String, window: DensityWindow, logPath: String) throws -> [DensityReport.LayerCoverage] {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        var blocks: [String: (cellArea: Double?, layerArea: Double?)] = [:]
        var current: String? = nil
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("DENSITY_LAYER ") {
                current = String(trimmed.dropFirst("DENSITY_LAYER ".count)).trimmingCharacters(in: .whitespaces)
                if let c = current { blocks[c] = blocks[c] ?? (nil, nil) }
            } else if let c = current {
                if let v = number(after: "Cell Area =", in: trimmed) { blocks[c]?.cellArea = v }
                else if let v = number(after: "Layer Total Area =", in: trimmed) { blocks[c]?.layerArea = v }
            }
        }

        var result: [DensityReport.LayerCoverage] = []
        for layer in window.layers {
            guard let block = blocks[layer], let cellArea = block.cellArea, cellArea > 0 else {
                throw DensityError.noCoverage(layer: layer, logPath: logPath)
            }
            let coverage = (block.layerArea ?? 0) / cellArea
            result.append(DensityReport.LayerCoverage(
                layer: layer, coverage: coverage,
                minDensity: window.minDensity, maxDensity: window.maxDensity))
        }
        return result
    }

    private func number(after prefix: String, in line: String) -> Double? {
        guard let range = line.range(of: prefix) else { return nil }
        let tail = line[range.upperBound...]
        let token = tail.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
        return token.flatMap(Double.init)
    }

    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> MagicDensitySignoff? {
        guard let driver = bundledDriverScriptURL else { return nil }
        let magicPath = environment["MAGIC_BIN"]
            ?? NSString(string: "~/.local/magic/bin/magic").expandingTildeInPath
        guard fileManager.isExecutableFile(atPath: magicPath) else { return nil }
        let context: SignoffPDKContext
        let rcFile: URL
        do {
            context = try SignoffPDKContext.resolve(
                requirementID: "magic",
                environment: environment,
                fileManager: fileManager
            )
            rcFile = try context.requiredFileURL(requirementID: "magic")
        } catch {
            return nil
        }
        guard fileManager.fileExists(atPath: rcFile.path(percentEncoded: false)) else { return nil }
        return MagicDensitySignoff(
            magicExecutableURL: URL(filePath: magicPath),
            rcFileURL: rcFile, pdkRoot: context.pdkRoot, driverScriptURL: driver)
    }
}
