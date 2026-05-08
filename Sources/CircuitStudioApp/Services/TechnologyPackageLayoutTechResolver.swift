import Foundation
import LayoutTech

public struct TechnologyPackageLayoutTechResolver: Sendable {
    public enum ResolverError: Error, LocalizedError, Equatable {
        case missingLayoutTechnologyReference
        case unsupportedBuiltinLayoutTechnology(String)
        case missingJSONPath
        case decodeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .missingLayoutTechnologyReference:
                return "Technology package does not define a layout technology reference."
            case .unsupportedBuiltinLayoutTechnology(let id):
                return "Unsupported builtin layout technology: \(id)"
            case .missingJSONPath:
                return "JSON layout technology reference requires a path."
            case .decodeFailed(let reason):
                return "Failed to decode layout technology database: \(reason)"
            }
        }
    }

    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    public func resolve(package: TechnologyPackage) throws -> LayoutTechDatabase {
        guard let reference = package.manifest.layoutTechnology else {
            throw ResolverError.missingLayoutTechnologyReference
        }
        switch reference.kind {
        case .builtin:
            return try resolveBuiltin(id: reference.id)
        case .json:
            guard let path = reference.path else {
                throw ResolverError.missingJSONPath
            }
            do {
                let data = try Data(contentsOf: package.resolvedURL(for: path))
                return try decoder.decode(LayoutTechDatabase.self, from: data)
            } catch {
                throw ResolverError.decodeFailed(error.localizedDescription)
            }
        }
    }

    private func resolveBuiltin(id: String?) throws -> LayoutTechDatabase {
        switch id {
        case "sampleProcess":
            return .sampleProcess()
        case "standard":
            return .standard()
        default:
            throw ResolverError.unsupportedBuiltinLayoutTechnology(id ?? "<missing>")
        }
    }
}
