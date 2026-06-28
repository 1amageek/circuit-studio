import Foundation
import LayoutCore
import LayoutIO
import LayoutTech

public struct StandardCellSignoffService: Sendable {
    public struct Output: Sendable {
        public let cellName: String
        public let gdsURL: URL
        public let schematicURL: URL
        public let review: ExternalSignoffReview

        public var passed: Bool {
            review.passed
        }
    }

    private let signoff: LiveSignoffService
    private let technology: LayoutTechDatabase

    public init(signoff: LiveSignoffService, technology: LayoutTechDatabase) {
        self.signoff = signoff
        self.technology = technology
    }

    public static func locate(
        technology: LayoutTechDatabase,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> StandardCellSignoffService? {
        LiveSignoffService.locate(environment: environment, fileManager: fileManager)
            .map { StandardCellSignoffService(signoff: $0, technology: technology) }
    }

    public func synthesize(
        _ generator: some StandardCellGenerator,
        name: String,
        into directory: URL
    ) async throws -> Output {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let gdsURL = directory.appending(path: "\(name).gds")
        try MaskDataFormatConverter(tech: technology)
            .exportDocument(generator.generate(name: name), to: gdsURL, format: .gds)

        let schematicURL = directory.appending(path: "\(name).spice")
        try generator.schematic(name: name).write(to: schematicURL, atomically: true, encoding: .utf8)

        let review = try await signoff.run(
            layoutGDS: gdsURL,
            topCell: name,
            schematicNetlist: schematicURL,
            artifactDirectory: directory
        )
        return Output(cellName: name, gdsURL: gdsURL, schematicURL: schematicURL, review: review)
    }

    public func synthesizeInverter(
        name: String,
        width: Double? = nil,
        into directory: URL,
        generator: ProfiledInverterGenerator
    ) async throws -> Output {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let document: LayoutDocument
        let schematic: String
        if let width {
            document = generator.generate(name: name, width: width)
            schematic = generator.schematic(name: name, width: width)
        } else {
            document = generator.generate(name: name)
            schematic = generator.schematic(name: name)
        }

        let gdsURL = directory.appending(path: "\(name).gds")
        try MaskDataFormatConverter(tech: technology)
            .exportDocument(document, to: gdsURL, format: .gds)

        let schematicURL = directory.appending(path: "\(name).spice")
        try schematic.write(to: schematicURL, atomically: true, encoding: .utf8)

        let review = try await signoff.run(
            layoutGDS: gdsURL,
            topCell: name,
            schematicNetlist: schematicURL,
            artifactDirectory: directory
        )
        return Output(cellName: name, gdsURL: gdsURL, schematicURL: schematicURL, review: review)
    }
}
