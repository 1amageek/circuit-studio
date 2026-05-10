import Foundation
import PEXEngine

public struct PEXArtifactService: Sendable {
    private let decoder: JSONDecoder

    public init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func loadArtifacts(manifestURL: URL) throws -> PEXRunArtifacts {
        let resolver: PEXArtifactResolver
        do {
            resolver = try PEXArtifactResolver(manifestURL: manifestURL)
        } catch {
            throw StudioError.projectLoadFailed("Failed to load PEX artifact manifest: \(error.localizedDescription)")
        }

        let manifest = resolver.manifest
        let corners = manifest.corners.map { corner in
            let rawURLs = resolver.records(kind: .rawOutput, cornerID: corner.cornerID, status: .available)
                .map { resolver.url(for: $0) }
            let irURL = resolver.records(kind: .parasiticIR, cornerID: corner.cornerID, status: .available)
                .first
                .map { resolver.url(for: $0) }
            let logURL = resolver.records(kind: .log, cornerID: corner.cornerID, status: .available)
                .first
                .map { resolver.url(for: $0) }
            return PEXCornerArtifacts(
                cornerID: corner.cornerID.value,
                status: corner.status.rawValue,
                rawFileURLs: rawURLs,
                irURL: irURL,
                logURL: logURL
            )
        }

        return PEXRunArtifacts(
            manifestURL: manifestURL,
            runID: manifest.runID.description,
            backendID: manifest.backendID,
            status: manifest.status.rawValue,
            corners: corners,
            warnings: manifest.warnings.map(\.message)
        )
    }

    public func loadIR(from url: URL) throws -> PEXParasiticIR {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StudioError.projectLoadFailed("Failed to read PEX IR: \(error.localizedDescription)")
        }

        let ir: IRDTO
        do {
            ir = try decoder.decode(IRDTO.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed("Failed to decode PEX IR: \(error.localizedDescription)")
        }

        let units = ir.units.parasiticUnits
        guard let resistanceScale = units.resistanceScaleToOhm else {
            throw StudioError.projectLoadFailed("Unsupported PEX resistance unit: \(units.resistance)")
        }
        guard let capacitanceScale = units.capacitanceScaleToFarad else {
            throw StudioError.projectLoadFailed("Unsupported PEX capacitance unit: \(units.capacitance)")
        }

        var elements: [PEXParasiticElement] = []
        var diagnostics: [PEXArtifactDiagnostic] = []

        for element in ir.elements {
            guard let kind = PEXParasiticElement.Kind(rawValue: element.kind) else {
                diagnostics.append(PEXArtifactDiagnostic(
                    severity: .warning,
                    message: "Unsupported PEX element kind '\(element.kind)' was ignored.",
                    elementID: element.id
                ))
                continue
            }

            guard element.value > 0 else {
                diagnostics.append(PEXArtifactDiagnostic(
                    severity: .warning,
                    message: "Non-positive PEX element value was ignored.",
                    elementID: element.id
                ))
                continue
            }

            let scale: Double
            switch kind {
            case .resistor:
                scale = resistanceScale
            case .capacitor, .coupling:
                scale = capacitanceScale
            }

            elements.append(PEXParasiticElement(
                id: element.id,
                kind: kind,
                nodeA: element.nodeA.spiceNodeName,
                nodeB: element.nodeB?.spiceNodeName,
                value: element.value * scale
            ))
        }

        return PEXParasiticIR(
            version: ir.version,
            cornerID: ir.cornerID.value,
            units: .canonical,
            elements: elements,
            diagnostics: diagnostics
        )
    }

    public func loadIR(for cornerID: String, artifacts: PEXRunArtifacts) throws -> PEXParasiticIR {
        do {
            let resolver = try PEXArtifactResolver(manifestURL: artifacts.manifestURL)
            let ir = try resolver.loadIR(cornerID: PEXCornerID(cornerID))
            return try convert(ir)
        } catch {
            if let corner = artifacts.corner(id: cornerID), let irURL = corner.irURL {
                return try loadIR(from: irURL)
            }
            throw StudioError.projectLoadFailed("PEX corner '\(cornerID)' has no readable IR artifact: \(error.localizedDescription)")
        }
    }

    public func auditArtifactURLs(manifestURL: URL, cornerID: String) throws -> [URL] {
        do {
            let resolver = try PEXArtifactResolver(manifestURL: manifestURL)
            let corner = PEXCornerID(cornerID)
            let records = resolver.records(kind: .rawOutput, cornerID: corner, status: .available)
                + resolver.records(kind: .parasiticIR, cornerID: corner, status: .available)
                + resolver.records(kind: .log, cornerID: corner, status: .available)
            return [manifestURL] + records.map { resolver.url(for: $0) }
        } catch {
            throw StudioError.projectLoadFailed("Failed to resolve PEX audit artifacts: \(error.localizedDescription)")
        }
    }

    private func convert(_ ir: ParasiticIR) throws -> PEXParasiticIR {
        var elements: [PEXParasiticElement] = []
        var diagnostics: [PEXArtifactDiagnostic] = []

        for element in ir.elements {
            guard let kind = PEXParasiticElement.Kind(rawValue: element.kind.rawValue) else {
                diagnostics.append(PEXArtifactDiagnostic(
                    severity: .warning,
                    message: "Unsupported PEX element kind '\(element.kind.rawValue)' was ignored.",
                    elementID: element.id
                ))
                continue
            }
            guard element.value > 0 else {
                diagnostics.append(PEXArtifactDiagnostic(
                    severity: .warning,
                    message: "Non-positive PEX element value was ignored.",
                    elementID: element.id
                ))
                continue
            }
            elements.append(PEXParasiticElement(
                id: element.id,
                kind: kind,
                nodeA: spiceNodeName(element.nodeA),
                nodeB: element.nodeB.map(spiceNodeName),
                value: element.value
            ))
        }

        return PEXParasiticIR(
            version: ir.version,
            cornerID: ir.cornerID.value,
            units: .canonical,
            elements: elements,
            diagnostics: diagnostics
        )
    }

    private func spiceNodeName(_ node: NodeRef) -> String {
        let nodeName = node.nodeName.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nodeName.isEmpty {
            return nodeName
        }
        return node.netName.value
    }
}

private struct IRDTO: Decodable {
    let version: String
    let cornerID: FlexibleValue
    let units: UnitsDTO
    let elements: [ElementDTO]

    private enum CodingKeys: String, CodingKey {
        case version, cornerID, units, elements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(String.self, forKey: .version)
        self.cornerID = try container.decode(FlexibleValue.self, forKey: .cornerID)
        self.units = try container.decodeIfPresent(UnitsDTO.self, forKey: .units) ?? UnitsDTO()
        self.elements = try container.decode([ElementDTO].self, forKey: .elements)
    }
}

private struct UnitsDTO: Decodable {
    let resistance: String
    let capacitance: String
    let coordinate: String

    init(resistance: String = "ohm", capacitance: String = "F", coordinate: String = "um") {
        self.resistance = resistance
        self.capacitance = capacitance
        self.coordinate = coordinate
    }

    private enum CodingKeys: String, CodingKey {
        case resistance, capacitance, coordinate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.resistance = try container.decodeIfPresent(String.self, forKey: .resistance) ?? "ohm"
        self.capacitance = try container.decodeIfPresent(String.self, forKey: .capacitance) ?? "F"
        self.coordinate = try container.decodeIfPresent(String.self, forKey: .coordinate) ?? "um"
    }

    var parasiticUnits: PEXParasiticUnits {
        PEXParasiticUnits(
            resistance: resistance,
            capacitance: capacitance,
            coordinate: coordinate
        )
    }
}

private struct ElementDTO: Decodable {
    let id: String
    let kind: String
    let nodeA: NodeRefDTO
    let nodeB: NodeRefDTO?
    let value: Double
}

private struct NodeRefDTO: Decodable {
    let netName: FlexibleValue
    let nodeName: FlexibleValue

    var spiceNodeName: String {
        let node = nodeName.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !node.isEmpty {
            return node
        }
        return netName.value
    }
}

private struct FlexibleValue: Decodable, Hashable {
    let value: String

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        do {
            let string = try single.decode(String.self)
            self.value = string
            return
        } catch DecodingError.typeMismatch(_, _) {
        } catch DecodingError.valueNotFound(_, _) {
        } catch {
            throw error
        }
        do {
            let uuid = try single.decode(UUID.self)
            self.value = uuid.uuidString
            return
        } catch DecodingError.typeMismatch(_, _) {
        } catch DecodingError.valueNotFound(_, _) {
        } catch {
            throw error
        }

        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        do {
            let string = try keyed.decode(String.self, forKey: .value)
            self.value = string
            return
        } catch DecodingError.typeMismatch(_, _) {
        } catch DecodingError.valueNotFound(_, _) {
        } catch {
            throw error
        }
        let uuid = try keyed.decode(UUID.self, forKey: .value)
        self.value = uuid.uuidString
    }

    private enum CodingKeys: String, CodingKey {
        case value
    }
}
