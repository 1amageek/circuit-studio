import CircuitStudioCore

/// Dependency injection container for all services.
@MainActor
public final class ServiceContainer {
    public let catalog: DeviceCatalog
    public let designFlowService: DesignFlowService
    public let waveformService: WaveformService
    public let designService: DesignService
    public let netlistGenerator: NetlistGenerator
    public let fileSystemService: FileSystemService
    public let netlistParsingService: NetlistParsingService
    public let projectService: ProjectService
    public let layoutPersistenceService: LayoutPersistenceService
    public let pexCommandService: PEXCommandService
    public let recentDocumentsStore: RecentDocumentsStore

    public init() {
        let catalog = DeviceCatalog.standard()
        let simulationService = SimulationService()
        self.catalog = catalog
        self.designFlowService = DesignFlowService(
            simulationService: simulationService,
            netlistGenerator: NetlistGenerator(catalog: catalog)
        )
        self.waveformService = WaveformService()
        self.designService = DesignService(catalog: catalog)
        self.netlistGenerator = NetlistGenerator(catalog: catalog)
        self.fileSystemService = FileSystemService()
        self.netlistParsingService = NetlistParsingService()
        let projectService = ProjectService()
        self.projectService = projectService
        self.layoutPersistenceService = LayoutPersistenceService(projectService: projectService)
        self.pexCommandService = PEXCommandService()
        self.recentDocumentsStore = RecentDocumentsStore()
    }
}
