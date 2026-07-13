import Foundation
import PEXEngine

public struct PEXArtifactService: Sendable {
    public init() {}

    public func loadManifest(manifestURL: URL) throws -> PEXArtifactManifest {
        do {
            return try PEXArtifactResolver(manifestURL: manifestURL).manifest
        } catch {
            throw StudioError.projectLoadFailed("Failed to load PEX artifact manifest: \(error.localizedDescription)")
        }
    }

    public func loadIR(for cornerID: String, manifestURL: URL) throws -> PEXParasiticIR {
        do {
            let resolver = try PEXArtifactResolver(manifestURL: manifestURL)
            let ir = try resolver.loadIR(cornerID: PEXCornerID(cornerID))
            return try convert(ir)
        } catch {
            throw StudioError.projectLoadFailed("PEX corner '\(cornerID)' has no readable IR artifact: \(error.localizedDescription)")
        }
    }

    public func loadCanonicalIR(for cornerID: String, manifestURL: URL) throws -> ParasiticIR {
        do {
            let resolver = try PEXArtifactResolver(manifestURL: manifestURL)
            return try resolver.loadIR(cornerID: PEXCornerID(cornerID))
        } catch {
            throw StudioError.projectLoadFailed(
                "PEX corner '\(cornerID)' has no readable canonical IR artifact: \(error.localizedDescription)"
            )
        }
    }

    public func auditArtifactURLs(manifestURL: URL, cornerID: String) throws -> [URL] {
        do {
            let resolver = try PEXArtifactResolver(manifestURL: manifestURL)
            let corner = PEXCornerID(cornerID)
            let records = resolver.records(kind: .rawOutput, cornerID: corner, status: .available)
                + resolver.records(kind: .parasiticIR, cornerID: corner, status: .available)
                + resolver.records(kind: .log, cornerID: corner, status: .available)
            let artifactURLs = try records.map { try resolver.validatedURL(for: $0) }
            return [manifestURL] + artifactURLs
        } catch {
            throw StudioError.projectLoadFailed("Failed to resolve PEX audit artifacts: \(error.localizedDescription)")
        }
    }

    private func convert(_ ir: ParasiticIR) throws -> PEXParasiticIR {
        var elements: [PEXParasiticElement] = []
        var diagnostics: [PEXArtifactDiagnostic] = []
        let resistanceScale = scaleToOhm(ir.units.resistance)
        let capacitanceScale = scaleToFarad(ir.units.capacitance)

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
            let scale: Double
            switch kind {
            case .resistor:
                scale = resistanceScale
            case .capacitor, .coupling:
                scale = capacitanceScale
            case .inductor:
                scale = 1.0
            }
            elements.append(PEXParasiticElement(
                id: element.id,
                kind: kind,
                nodeA: spiceNodeName(element.nodeA),
                nodeB: element.nodeB.map(spiceNodeName),
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

    private func spiceNodeName(_ node: NodeRef) -> String {
        let nodeName = node.nodeName.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nodeName.isEmpty {
            return nodeName
        }
        return node.netName.value
    }

    private func scaleToOhm(_ unit: ParasiticUnits.ResistanceUnit) -> Double {
        switch unit {
        case .ohm:
            return 1.0
        case .kiloOhm:
            return 1.0e3
        }
    }

    private func scaleToFarad(_ unit: ParasiticUnits.CapacitanceUnit) -> Double {
        switch unit {
        case .farad:
            return 1.0
        case .picoFarad:
            return 1.0e-12
        case .femtoFarad:
            return 1.0e-15
        }
    }
}
