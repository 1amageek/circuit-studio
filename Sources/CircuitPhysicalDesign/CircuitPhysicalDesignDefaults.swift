import LayoutEngine

public enum CircuitPhysicalDesignDefaults {
    public static func layoutEngineCatalog() -> LayoutEngineCatalog {
        LayoutEngineCatalog.standard().registering(
            PostRouteVerifierRegistration(
                descriptor: LayoutEngineDescriptor(
                    id: "drc-post-route-verifier",
                    name: "DRC Post-Route Verifier",
                    version: "1.0",
                    role: .postRouteVerification,
                    summary: "Runs in-process DRC and returns repair-triggering route violations.",
                    isDeterministic: true,
                    source: "circuit-physical-design"
                ),
                makeVerifier: { tech in DRCPostRouteVerifier(tech: tech) }
            )
        )
    }
}
