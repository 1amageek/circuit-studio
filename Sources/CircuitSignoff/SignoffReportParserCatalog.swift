public struct SignoffReportParserCatalog: Sendable {
    public init() {}

    public func parser(for styleID: String) throws -> ExternalSignoffReportParser {
        switch styleID {
        case "generic-command":
            return ExternalSignoffReportParser(style: .generic)
        case "calibre-like", "golden-log-replay":
            return ExternalSignoffReportParser(style: .calibreLike)
        case "magic-netgen-like":
            return ExternalSignoffReportParser(style: .magicNetgenLike)
        case "klayout-like":
            return ExternalSignoffReportParser(style: .klayoutLike)
        default:
            throw SignoffReportParserCatalogError.unsupportedStyleID(styleID)
        }
    }
}
