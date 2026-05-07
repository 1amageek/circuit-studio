import Foundation

public struct PEXRunArtifacts: Sendable, Hashable {
    public let manifestURL: URL
    public let runID: String
    public let backendID: String
    public let status: String
    public let corners: [PEXCornerArtifacts]
    public let warnings: [String]

    public init(
        manifestURL: URL,
        runID: String,
        backendID: String,
        status: String,
        corners: [PEXCornerArtifacts],
        warnings: [String]
    ) {
        self.manifestURL = manifestURL
        self.runID = runID
        self.backendID = backendID
        self.status = status
        self.corners = corners
        self.warnings = warnings
    }

    public func corner(id: String) -> PEXCornerArtifacts? {
        corners.first { $0.cornerID == id }
    }
}

public struct PEXCornerArtifacts: Sendable, Hashable {
    public let cornerID: String
    public let status: String
    public let rawFileURLs: [URL]
    public let irURL: URL?
    public let logURL: URL?

    public init(
        cornerID: String,
        status: String,
        rawFileURLs: [URL],
        irURL: URL?,
        logURL: URL?
    ) {
        self.cornerID = cornerID
        self.status = status
        self.rawFileURLs = rawFileURLs
        self.irURL = irURL
        self.logURL = logURL
    }
}

public struct PEXParasiticIR: Sendable, Hashable {
    public let version: String
    public let cornerID: String
    public let units: PEXParasiticUnits
    public let elements: [PEXParasiticElement]
    public let diagnostics: [PEXArtifactDiagnostic]

    public init(
        version: String,
        cornerID: String,
        units: PEXParasiticUnits = .canonical,
        elements: [PEXParasiticElement],
        diagnostics: [PEXArtifactDiagnostic] = []
    ) {
        self.version = version
        self.cornerID = cornerID
        self.units = units
        self.elements = elements
        self.diagnostics = diagnostics
    }
}

public struct PEXParasiticUnits: Sendable, Hashable {
    public let resistance: String
    public let capacitance: String
    public let coordinate: String

    public init(resistance: String, capacitance: String, coordinate: String) {
        self.resistance = resistance
        self.capacitance = capacitance
        self.coordinate = coordinate
    }

    public static let canonical = PEXParasiticUnits(
        resistance: "ohm",
        capacitance: "F",
        coordinate: "um"
    )

    public var resistanceScaleToOhm: Double? {
        switch resistance {
        case "ohm": return 1.0
        case "kohm": return 1.0e3
        default: return nil
        }
    }

    public var capacitanceScaleToFarad: Double? {
        switch capacitance {
        case "F": return 1.0
        case "pF": return 1.0e-12
        case "fF": return 1.0e-15
        default: return nil
        }
    }
}

public struct PEXParasiticElement: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case resistor
        case capacitor
        case coupling
    }

    public let id: String
    public let kind: Kind
    public let nodeA: String
    public let nodeB: String?
    public let value: Double

    public init(id: String, kind: Kind, nodeA: String, nodeB: String?, value: Double) {
        self.id = id
        self.kind = kind
        self.nodeA = nodeA
        self.nodeB = nodeB
        self.value = value
    }
}

public struct PEXArtifactDiagnostic: Sendable, Hashable {
    public enum Severity: String, Sendable, Hashable {
        case warning
        case error
    }

    public let severity: Severity
    public let message: String
    public let elementID: String?

    public init(severity: Severity, message: String, elementID: String? = nil) {
        self.severity = severity
        self.message = message
        self.elementID = elementID
    }
}
