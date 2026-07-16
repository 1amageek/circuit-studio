import Foundation
import CircuitStudioCore
import PEXEngine

public struct TechnologyPackageLoader: Sendable {
    public enum LoaderError: Error, LocalizedError, Equatable {
        case manifestReadFailed(String)
        case manifestDecodeFailed(String)
        case processTechnologyDecodeFailed(String)
        case pexProjectConfigDecodeFailed(String)
        case validationFailed(TechnologyPackageValidationReport)

        public var errorDescription: String? {
            switch self {
            case .manifestReadFailed(let reason):
                return "Failed to read technology package manifest: \(reason)"
            case .manifestDecodeFailed(let reason):
                return "Failed to decode technology package manifest: \(reason)"
            case .processTechnologyDecodeFailed(let reason):
                return "Failed to decode process technology: \(reason)"
            case .pexProjectConfigDecodeFailed(let reason):
                return "Failed to decode PEX project config: \(reason)"
            case .validationFailed(let report):
                return report.errors.map(\.message).joined(separator: "; ")
            }
        }
    }

    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    public func load(manifestURL: URL) throws -> TechnologyPackage {
        let manifest = try decodeManifest(manifestURL: manifestURL)
        let rootURL = manifestURL.deletingLastPathComponent()
        let validationReport = validate(manifest: manifest, rootURL: rootURL)
        guard validationReport.isValid else {
            throw LoaderError.validationFailed(validationReport)
        }

        let processConfiguration = try loadProcessConfiguration(
            manifest: manifest,
            rootURL: rootURL
        )
        let pexProjectConfig = try loadPEXProjectConfig(
            manifest: manifest,
            rootURL: rootURL
        )
        return TechnologyPackage(
            manifestURL: manifestURL,
            rootURL: rootURL,
            manifest: manifest,
            processConfiguration: processConfiguration,
            pexProjectConfig: pexProjectConfig,
            validationReport: validationReport
        )
    }

    public func validate(manifestURL: URL) throws -> TechnologyPackageValidationReport {
        let manifest = try decodeManifest(manifestURL: manifestURL)
        return validate(manifest: manifest, rootURL: manifestURL.deletingLastPathComponent())
    }

    public func validate(
        manifest: TechnologyPackageManifest,
        rootURL: URL
    ) -> TechnologyPackageValidationReport {
        var diagnostics: [TechnologyPackageValidationReport.Diagnostic] = []

        if manifest.version != 1 {
            diagnostics.append(.init(
                severity: .error,
                code: "unsupported_version",
                message: "Technology package version \(manifest.version) is not supported."
            ))
        }
        if manifest.packageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(.init(
                severity: .error,
                code: "missing_package_id",
                message: "Technology package requires a non-empty packageID."
            ))
        }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(.init(
                severity: .error,
                code: "missing_name",
                message: "Technology package requires a non-empty name."
            ))
        }

        validateFile(manifest.processTechnologyPath, rootURL: rootURL, code: "missing_process_technology", diagnostics: &diagnostics)
        for path in manifest.spiceModelSearchPaths {
            validatePath(path, rootURL: rootURL, code: "missing_spice_model_search_path", diagnostics: &diagnostics)
        }
        if let layoutTechnology = manifest.layoutTechnology {
            validateLayoutTechnology(layoutTechnology, rootURL: rootURL, diagnostics: &diagnostics)
        } else {
            diagnostics.append(.init(
                severity: .warning,
                code: "missing_layout_technology",
                message: "No layout technology reference is configured."
            ))
        }
        validateFile(manifest.layerMapPath, rootURL: rootURL, code: "missing_layer_map", diagnostics: &diagnostics)
        validateSignoff(manifest.signoff, rootURL: rootURL, diagnostics: &diagnostics)
        validateFile(manifest.pex?.projectConfigPath, rootURL: rootURL, code: "missing_pex_project_config", diagnostics: &diagnostics)
        validateFile(manifest.pex?.savedManifestPath, rootURL: rootURL, code: "missing_saved_pex_manifest", diagnostics: &diagnostics)
        validateFile(manifest.corpus?.goldenLayoutManifestPath, rootURL: rootURL, code: "missing_golden_layout_manifest", diagnostics: &diagnostics)

        return TechnologyPackageValidationReport(diagnostics: diagnostics)
    }

    private func decodeManifest(manifestURL: URL) throws -> TechnologyPackageManifest {
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw LoaderError.manifestReadFailed(error.localizedDescription)
        }

        do {
            return try decoder.decode(TechnologyPackageManifest.self, from: data)
        } catch {
            throw LoaderError.manifestDecodeFailed(error.localizedDescription)
        }
    }

    private func loadProcessConfiguration(
        manifest: TechnologyPackageManifest,
        rootURL: URL
    ) throws -> ProcessConfiguration? {
        guard let path = manifest.processTechnologyPath else {
            return nil
        }
        do {
            let data = try Data(contentsOf: resolvedURL(path, rootURL: rootURL))
            let technology = try decoder.decode(ProcessTechnology.self, from: data)
            return ProcessConfiguration(
                technology: technology,
                cornerID: manifest.corners.first?.processCornerID ?? technology.defaultCornerID,
                includePaths: manifest.spiceModelSearchPaths.map { resolvedURL($0, rootURL: rootURL).path(percentEncoded: false) },
                resolveIncludes: true
            )
        } catch {
            throw LoaderError.processTechnologyDecodeFailed(error.localizedDescription)
        }
    }

    private func loadPEXProjectConfig(
        manifest: TechnologyPackageManifest,
        rootURL: URL
    ) throws -> PEXProjectConfig? {
        guard let path = manifest.pex?.projectConfigPath else {
            return nil
        }
        do {
            let data = try Data(contentsOf: resolvedURL(path, rootURL: rootURL))
            return try decoder.decode(PEXProjectConfig.self, from: data)
        } catch {
            throw LoaderError.pexProjectConfigDecodeFailed(error.localizedDescription)
        }
    }

    private func validateLayoutTechnology(
        _ reference: TechnologyPackageManifest.LayoutTechnologyReference,
        rootURL: URL,
        diagnostics: inout [TechnologyPackageValidationReport.Diagnostic]
    ) {
        switch reference.kind {
        case .builtin:
            let supportedIDs = ["sampleProcess", "standard"]
            guard let id = reference.id, supportedIDs.contains(id) else {
                diagnostics.append(.init(
                    severity: .error,
                    code: "unsupported_builtin_layout_technology",
                    message: "Unsupported builtin layout technology: \(reference.id ?? "<missing>")."
                ))
                return
            }
        case .json:
            validateFile(reference.path, rootURL: rootURL, code: "missing_layout_technology_json", diagnostics: &diagnostics)
        }
    }

    private func validateSignoff(
        _ signoff: TechnologyPackageManifest.SignoffReference?,
        rootURL: URL,
        diagnostics: inout [TechnologyPackageValidationReport.Diagnostic]
    ) {
        guard let signoff else {
            diagnostics.append(.init(
                severity: .warning,
                code: "missing_signoff_reference",
                message: "No signoff adapter reference is configured."
            ))
            return
        }
        if signoff.adapterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(.init(
                severity: .error,
                code: "missing_signoff_adapter",
                message: "Signoff adapterID must not be empty."
            ))
        }
        validateFile(signoff.drc?.replayLogPath, rootURL: rootURL, code: "missing_drc_replay_log", diagnostics: &diagnostics)
        validateFile(signoff.lvs?.replayLogPath, rootURL: rootURL, code: "missing_lvs_replay_log", diagnostics: &diagnostics)
    }

    private func validateFile(
        _ path: String?,
        rootURL: URL,
        code: String,
        diagnostics: inout [TechnologyPackageValidationReport.Diagnostic]
    ) {
        guard let path else { return }
        let url = resolvedURL(path, rootURL: rootURL)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory), !isDirectory.boolValue else {
            diagnostics.append(.init(
                severity: .error,
                code: code,
                message: "Required file is missing: \(path)",
                path: path
            ))
            return
        }
    }

    private func validatePath(
        _ path: String,
        rootURL: URL,
        code: String,
        diagnostics: inout [TechnologyPackageValidationReport.Diagnostic]
    ) {
        let url = resolvedURL(path, rootURL: rootURL)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            diagnostics.append(.init(
                severity: .error,
                code: code,
                message: "Required path is missing: \(path)",
                path: path
            ))
            return
        }
    }

    private func resolvedURL(_ path: String, rootURL: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(filePath: path)
        }
        return rootURL.appending(path: path)
    }
}
