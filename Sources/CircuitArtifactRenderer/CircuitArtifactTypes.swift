import ArtifactCore

public enum CircuitArtifactTypes {
    public static let waveformCSV: ArtifactType = "application/vnd.xcircuite.waveform+csv"
    public static let waveformRAW: ArtifactType = "application/vnd.xcircuite.waveform-raw"
    public static let spice: ArtifactType = "text/vnd.xcircuite.spice"
    public static let lef: ArtifactType = "text/vnd.xcircuite.lef"
    public static let def: ArtifactType = "text/vnd.xcircuite.def"
    public static let spef: ArtifactType = "text/vnd.xcircuite.spef"
    public static let oasis: ArtifactType = "application/vnd.xcircuite.oasis"
    public static let gdsii: ArtifactType = "application/vnd.xcircuite.gdsii"
    public static let raw: ArtifactType = "application/vnd.xcircuite.raw"
}
