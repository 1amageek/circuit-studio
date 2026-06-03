import Foundation
import Testing
@testable import CircuitStudioApp

/// BC4 / DoD-6 — the autonomous single-call flow: from an intent (program + target clock) it
/// closes functional + timing (always) and physical (when the toolchain is present), emits a
/// GDS, and produces a machine-checkable evidence bundle — no human in the loop.
@Suite("Spec-to-silicon flow")
struct SpecToSiliconFlowTests {

    static let fibonacci = """
        LDI 1
        STA 0
        STA 1
        loop: LDA 0
        ADD 1
        STA 2
        LDA 1
        STA 0
        LDA 2
        STA 1
        JMP loop
        """

    private func intent() throws -> SpecToSiliconFlow.Intent {
        SpecToSiliconFlow.Intent(designName: "acc4flow",
                                 program: try ACC4Assembler().assemble(Self.fibonacci),
                                 cycles: 60, targetClockPeriod: 5e-9)
    }

    @Test("Autonomous functional + timing closure yields a verifiable bundle (tool-independent)",
          .timeLimit(.minutes(6)))
    func functionalTimingBundle() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "flow-\(UUID().uuidString)")
        let result = try await SpecToSiliconFlow(
            runPhysical: false,
            timingLibraryBuilder: CachedStandardTimingLibraryBuilder(),
            spiceValidator: CachedTimingPathValidator()
        ).run(try intent(), artifactDirectory: dir)

        #expect(result.bundle.claim(.functional)?.passed == true)
        #expect(result.bundle.claim(.timing)?.passed == true)
        #expect(result.bundle.supportingClaims(for: .antenna).contains {
            $0.statement == TapeoutEvidenceBundle.Claim.antennaProtectionPlanStatement
        })
        #expect(result.bundle.claim(.antenna) == nil)
        // The functional + timing axes verify, and their artifacts are on disk.
        try result.bundle.verify(requiredAxes: [.functional, .timing], runDirectory: dir)
        #expect(throws: TapeoutEvidenceBundle.VerificationError.missingAxis(.antenna)) {
            try result.bundle.verify(requiredAxes: [.antenna], runDirectory: dir)
        }
        let evidenceURL = dir.appending(path: "acc4flow.evidence.json")
        #expect(FileManager.default.fileExists(atPath: evidenceURL.path))
        let persistedBundle = try JSONDecoder().decode(TapeoutEvidenceBundle.self, from: Data(contentsOf: evidenceURL))
        #expect(persistedBundle.schemaVersion == TapeoutEvidenceBundle.currentSchemaVersion)
        #expect(persistedBundle.supportingClaims(for: .antenna).contains {
            $0.kind == .supportingEvidence
                && $0.statement == TapeoutEvidenceBundle.Claim.antennaProtectionPlanStatement
        })
        // Requiring the physical axes (not run) must FAIL — honest, never a silent pass.
        #expect(throws: TapeoutEvidenceBundle.VerificationError.self) {
            try result.bundle.verify(requiredAxes: [.functional, .timing, .drc, .lvs])
        }
    }

    @Test("Full autonomous flow runs the WHOLE physical deck and reports it truthfully",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(12)))
    func fullBundleSignsOff() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "flow-full-\(UUID().uuidString)")
        let result = try await SpecToSiliconFlow(
            runPhysical: true,
            timingLibraryBuilder: CachedStandardTimingLibraryBuilder(),
            spiceValidator: CachedTimingPathValidator()
        ).run(try intent(), artifactDirectory: dir)

        // The whole deck ran: functional + timing + every physical axis is present.
        for axis in [TapeoutEvidenceBundle.Axis.functional, .timing, .erc, .drc, .lvs, .antenna, .density, .ir, .em] {
            #expect(result.bundle.claim(axis) != nil, "axis \(axis) must be present in the bundle")
        }
        let gds = try #require(result.gdsPath)
        #expect(FileManager.default.fileExists(atPath: gds.path))

        let antennaPlan = dir.appending(path: "acc4flow.antenna-protection.json")
        #expect(FileManager.default.fileExists(atPath: antennaPlan.path))
        let decodedPlan = try JSONDecoder().decode(AntennaProtectionPlan.self, from: Data(contentsOf: antennaPlan))
        #expect(decodedPlan.ruleSet.protectsLocalGateContacts)
        #expect(!decodedPlan.sites.isEmpty)
        #expect(Set(decodedPlan.sites.map(\.strategy)) == [.diffusionTie])
        #expect(decodedPlan.sites.allSatisfy { !$0.id.isEmpty && !$0.instanceName.isEmpty && !$0.gateName.isEmpty })
        #expect(result.bundle.claims(for: .antenna).contains {
            $0.artifact?.path == "acc4flow.antenna-protection.json"
                && $0.kind == .supportingEvidence
                && $0.statement == TapeoutEvidenceBundle.Claim.antennaProtectionPlanStatement
        })
        #expect(result.bundle.signoffClaims(for: .antenna).contains {
            $0.statement == "no gate-oxide antenna violations"
        })

        // The ACC-4 core is DRC/LVS/ERC/density/IR/EM clean, and the generated antenna
        // protection closes local gate-contact met1 risers before Magic antennacheck runs.
        #expect(result.bundle.claim(.drc)?.passed == true)
        #expect(result.bundle.claim(.lvs)?.passed == true)
        #expect(result.bundle.claim(.erc)?.passed == true)
        #expect(result.bundle.claim(.ir)?.passed == true)
        #expect(result.bundle.claim(.em)?.passed == true)
        #expect(result.bundle.claim(.density)?.passed == true)
        #expect(result.bundle.claim(.antenna)?.passed == true)

        #expect(result.bundle.passed)
        #expect(result.bundle.failing.isEmpty)
        try result.bundle.verify(
            requiredAxes: [.functional, .timing, .drc, .lvs, .antenna, .density, .ir, .em],
            runDirectory: dir
        )
    }

    @Test("Sequential timing report without a measured grid point fails loud", .timeLimit(.minutes(1)))
    func missingSequentialTimingGridFailsLoud() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "flow-empty-grid-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: dir)
            } catch {
                Issue.record("Failed to remove temporary flow directory: \(error)")
            }
        }

        await #expect(throws: SpecToSiliconFlow.FlowError.missingSequentialTimingGridPoint) {
            _ = try await SpecToSiliconFlow(
                runPhysical: false,
                timingLibraryBuilder: EmptySequentialGridTimingLibraryBuilder(),
                spiceValidator: PassingTimingPathValidator()
            ).run(try intent(), artifactDirectory: dir)
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "timing/timing-library.json").path))
    }

    private struct PassingTimingPathValidator: TimingPathValidating {
        func validate(
            path: TimingPath,
            in netlist: SequentialNetlist,
            toleranceFraction: Double
        ) async throws -> STAvsSPICEValidator.Result {
            STAvsSPICEValidator.Result(
                staDelay: path.combinationalDelay,
                spiceDelay: path.combinationalDelay,
                relativeError: 0,
                tolerance: toleranceFraction
            )
        }
    }

    private struct EmptySequentialGridTimingLibraryBuilder: TimingLibraryBuilding {
        func buildStandardLibrary(runID: String?) async throws -> StandardTimingLibraryBuildResult {
            let technology = TimingTechnologyContext(
                processName: "test",
                cornerID: "tt",
                supplyVoltage: 1.8,
                deviceModelID: "unit"
            )
            let library = Self.constantLibrary()
            let sequentialReport = SequentialTimingCharacterizationReport(
                cellName: "dff",
                topologyHash: "hash",
                activeClockEdge: .rising,
                technology: technology,
                characterizationGrid: SequentialTimingCharacterizationGrid(
                    clockSlews: [],
                    dataSlews: [80e-12],
                    outputLoads: [],
                    setupHoldSearchResolution: 10e-12,
                    setupHoldSearchWindow: 100e-12
                ),
                timing: try library.sequential(),
                clkToQMeasurements: [],
                qTransitionMeasurements: [],
                setupMeasurements: [],
                holdMeasurements: [],
                status: .passed
            )
            return StandardTimingLibraryBuildResult(
                library: library,
                libraryArtifact: TimingLibraryArtifact(
                    runID: runID,
                    technology: technology,
                    library: library,
                    modelSources: [
                        TimingModelSource(
                            modelID: "dff",
                            modelKind: .sequentialCell,
                            sourceType: .characterized,
                            artifactIDs: ["sequential-dff-characterization"]
                        ),
                    ]
                ),
                combinationalReport: CombinationalTimingCharacterizationReport(
                    technology: technology,
                    inputSlews: [50e-12],
                    outputLoads: [1e-15],
                    cells: [],
                    status: .passed
                ),
                sequentialReport: sequentialReport
            )
        }

        private static func constantLibrary() -> TimingLibrary {
            func arc(_ pin: String, _ delay: Double) -> TimingArc {
                TimingArc(
                    inputPin: pin,
                    sense: .negativeUnate,
                    delayRise: .constant(delay),
                    delayFall: .constant(delay),
                    transitionRise: .constant(20e-12),
                    transitionFall: .constant(20e-12)
                )
            }
            let inv = CellTiming(cellName: "inv", inputCapacitance: ["A": 1e-15], arcs: [arc("A", 30e-12)])
            let nand = CellTiming(
                cellName: "nand2",
                inputCapacitance: ["A": 1e-15, "B": 1e-15],
                arcs: [arc("A", 60e-12), arc("B", 60e-12)]
            )
            let nor = CellTiming(
                cellName: "nor2",
                inputCapacitance: ["A": 1e-15, "B": 1e-15],
                arcs: [arc("A", 70e-12), arc("B", 70e-12)]
            )
            let ff = SequentialTiming(
                clkToQRise: .constant(100e-12),
                clkToQFall: .constant(100e-12),
                qTransitionRise: .constant(20e-12),
                qTransitionFall: .constant(20e-12),
                setupTime: 20e-12,
                holdTime: 5e-12,
                dataCapacitance: 1e-15,
                clockCapacitance: 1e-15
            )
            return TimingLibrary(cells: ["inv": inv, "nand2": nand, "nor2": nor], flipFlop: ff)
        }
    }
}
