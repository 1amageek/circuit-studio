import Foundation

public enum SignoffReportParserCatalogError: Error, LocalizedError, Equatable {
    case unsupportedStyleID(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedStyleID(let styleID):
            return "Unsupported signoff report style ID: \(styleID)"
        }
    }
}
