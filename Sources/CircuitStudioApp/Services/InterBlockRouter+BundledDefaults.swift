import CircuitPhysicalDesign

public extension InterBlockRouter {
    static func bundledDefault() throws -> InterBlockRouter {
        InterBlockRouter(profile: try LayoutTechnologyCatalog.loadDefaultRoutingProfile())
    }

    init() throws {
        self.init(profile: try LayoutTechnologyCatalog.loadDefaultRoutingProfile())
    }
}
