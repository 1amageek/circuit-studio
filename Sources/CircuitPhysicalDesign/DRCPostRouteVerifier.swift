import Foundation
import LayoutCore
import LayoutTech
import LayoutAutoGen
import LayoutVerify

/// Bridges the real DRC service into the routing repair loop: runs full
/// DRC on the assembled document and reports error-severity violations
/// with their shape/via/net attribution. Warnings stay out so the loop
/// neither rips up nets for advisory findings nor reports them as
/// unresolved.
struct DRCPostRouteVerifier: PostRouteVerifier {
    let tech: LayoutTechDatabase

    func verify(document: LayoutDocument) throws -> [PostRouteViolation] {
        let result = LayoutDRCService().run(document: document, tech: tech)
        // Antenna violations are excluded: rip-up and reroute reproduces the
        // same topology and cannot reduce charge-collection area, so they are
        // handled by the dedicated jumper-insertion pass after this loop.
        return result.violations
            .filter { $0.severity == .error && $0.kind != .antenna }
            .map { violation in
                PostRouteViolation(
                    message: violation.message,
                    layer: violation.layer,
                    region: violation.region,
                    shapeIDs: violation.shapeIDs,
                    viaIDs: violation.viaIDs,
                    netIDs: violation.netIDs
                )
            }
    }
}
