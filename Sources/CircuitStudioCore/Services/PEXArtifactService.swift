import Foundation

public struct PEXArtifactService: Sendable {
    private let decoder: JSONDecoder

    public init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func loadArtifacts(manifestURL: URL) throws -> PEXRunArtifacts {
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw StudioError.projectLoadFailed("Failed to read PEX manifest: \(error.localizedDescription)")
        }

        let manifest: ManifestDTO
        do {
            manifest = try decoder.decode(ManifestDTO.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed("Failed to decode PEX manifest: \(error.localizedDescription)")
        }

        let runDirectory = manifestURL.deletingLastPathComponent()
        let corners = manifest.corners.map { corner in
            PEXCornerArtifacts(
                cornerID: corner.cornerID.value,
                status: corner.status,
                rawFileURLs: corner.rawFiles.map {
                    runDirectory.appending(path: "raw")
                        .appending(path: corner.cornerID.value)
                        .appending(path: $0)
                },
                irURL: corner.irFile.map { resolveIRURL($0, cornerID: corner.cornerID.value, runDirectory: runDirectory) },
                logURL: corner.logFile.map {
                    runDirectory.appending(path: "raw")
                        .appending(path: corner.cornerID.value)
                        .appending(path: $0)
                }
            )
        }

        return PEXRunArtifacts(
            manifestURL: manifestURL,
            runID: manifest.runID.value,
            backendID: manifest.backendID,
            status: manifest.status,
            corners: corners,
            warnings: manifest.warnings
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
        guard let corner = artifacts.corner(id: cornerID) else {
            throw StudioError.projectLoadFailed("PEX corner '\(cornerID)' was not found in manifest.")
        }
        guard let irURL = corner.irURL else {
            throw StudioError.projectLoadFailed("PEX corner '\(cornerID)' has no IR artifact.")
        }
        return try loadIR(from: irURL)
    }

    private func resolveIRURL(_ fileName: String, cornerID: String, runDirectory: URL) -> URL {
        let expanded = NSString(string: fileName).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(filePath: expanded)
        }
        if fileName.contains("/") {
            return runDirectory.appending(path: fileName)
        }
        return runDirectory.appending(path: "ir").appending(path: fileName.isEmpty ? "\(cornerID).json" : fileName)
    }
}

private struct ManifestDTO: Decodable {
    let runID: FlexibleValue
    let backendID: String
    let status: String
    let corners: [CornerDTO]
    let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case runID, backendID, status, corners, warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.runID = try container.decode(FlexibleValue.self, forKey: .runID)
        self.backendID = try container.decode(String.self, forKey: .backendID)
        self.status = try container.decode(String.self, forKey: .status)
        self.corners = try container.decode([CornerDTO].self, forKey: .corners)
        self.warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

private struct CornerDTO: Decodable {
    let cornerID: FlexibleValue
    let status: String
    let rawFiles: [String]
    let irFile: String?
    let logFile: String?
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
