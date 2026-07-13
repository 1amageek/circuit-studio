import ArtifactCore
import CircuiteFoundation

public struct XcircuiteArtifactTypeResolver: CircuitArtifactTypeResolving, Sendable {
    public init() {}

    public func artifactType(
        kind: ArtifactKind,
        format: ArtifactFormat
    ) -> ArtifactType? {
        if kind == .waveform {
            switch format.rawValue {
            case ArtifactFormat.csv.rawValue:
                return CircuitArtifactTypes.waveformCSV
            case ArtifactFormat.raw.rawValue:
                return CircuitArtifactTypes.waveformRAW
            default:
                break
            }
        }

        switch format.rawValue {
        case ArtifactFormat.json.rawValue:
            return .json
        case ArtifactFormat.csv.rawValue:
            return .csv
        case ArtifactFormat.text.rawValue:
            return .plainText
        case ArtifactFormat.systemVerilog.rawValue, ArtifactFormat.verilog.rawValue,
             ArtifactFormat.dspf.rawValue, ArtifactFormat.liberty.rawValue,
             ArtifactFormat.sdc.rawValue, ArtifactFormat.sdf.rawValue,
             ArtifactFormat.upf.rawValue, ArtifactFormat.cpf.rawValue,
             ArtifactFormat.vcd.rawValue, ArtifactFormat.fst.rawValue,
             ArtifactFormat.stil.rawValue, ArtifactFormat.wgl.rawValue:
            return .plainText
        case ArtifactFormat.spice.rawValue:
            return CircuitArtifactTypes.spice
        case ArtifactFormat.lef.rawValue:
            return CircuitArtifactTypes.lef
        case ArtifactFormat.def.rawValue:
            return CircuitArtifactTypes.def
        case ArtifactFormat.spef.rawValue:
            return CircuitArtifactTypes.spef
        case ArtifactFormat.oasis.rawValue:
            return CircuitArtifactTypes.oasis
        case ArtifactFormat.gdsii.rawValue:
            return CircuitArtifactTypes.gdsii
        case ArtifactFormat.raw.rawValue:
            return CircuitArtifactTypes.raw
        case ArtifactFormat.unknown.rawValue:
            return nil
        default:
            return .plainText
        }
    }
}
