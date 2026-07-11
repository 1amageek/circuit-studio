import ArtifactCore
import XcircuitePackage

public struct XcircuiteArtifactTypeResolver: CircuitArtifactTypeResolving, Sendable {
    public init() {}

    public func artifactType(
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat
    ) -> ArtifactType? {
        if kind == .waveform {
            switch format {
            case .csv:
                return CircuitArtifactTypes.waveformCSV
            case .raw:
                return CircuitArtifactTypes.waveformRAW
            default:
                break
            }
        }

        switch format {
        case .json:
            return .json
        case .csv:
            return .csv
        case .text:
            return .plainText
        case .spice:
            return CircuitArtifactTypes.spice
        case .lef:
            return CircuitArtifactTypes.lef
        case .def:
            return CircuitArtifactTypes.def
        case .spef:
            return CircuitArtifactTypes.spef
        case .oasis:
            return CircuitArtifactTypes.oasis
        case .gdsii:
            return CircuitArtifactTypes.gdsii
        case .raw:
            return CircuitArtifactTypes.raw
        case .unknown:
            return nil
        }
    }
}
