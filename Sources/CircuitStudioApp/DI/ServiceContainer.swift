import CircuitStudioCore

/// Dependency injection container for all services.
@MainActor
public final class ServiceContainer {
    public let catalog: DeviceCatalog
    public let simulationService: SimulationService
    public let waveformService: WaveformService
    public let designService: DesignService
    public let netlistGenerator: NetlistGenerator
    public let fileSystemService: FileSystemService
    public let netlistParsingService: NetlistParsingService

    public init() {
        let catalog = DeviceCatalog.standard()
        self.catalog = catalog
        self.simulationService = SimulationService()
        self.waveformService = WaveformService()
        self.designService = DesignService(catalog: catalog)
        self.netlistGenerator = NetlistGenerator(catalog: catalog)
        self.fileSystemService = FileSystemService()
        self.netlistParsingService = NetlistParsingService()
    }
}
