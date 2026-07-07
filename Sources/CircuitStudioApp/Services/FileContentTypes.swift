import UniformTypeIdentifiers

enum FileContentTypes {
    static let spiceOpen = extensions(["cir", "spice"], fallback: [.plainText])
    static let spiceSave = extensions(["cir", "spice"])
    static let layoutExport = extensions(["gds", "oas"])
    static let technologyImport = extensions(["json", "lef", "lyp"])
    static let processImport = extensions(["json"], fallback: [.plainText])

    private static func extensions(_ values: [String], fallback: [UTType] = []) -> [UTType] {
        values.compactMap { UTType(filenameExtension: $0) } + fallback
    }
}
