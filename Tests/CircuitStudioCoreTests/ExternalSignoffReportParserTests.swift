import CircuitSignoff
import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("ExternalSignoffReportParser generic")
struct GenericExternalSignoffReportParserTests {

    private let parser = ExternalSignoffReportParser(style: .generic)

    private func report(_ rawOutput: String, success: Bool = true) -> ExternalSignoffToolReport {
        parser.parse(
            kind: .drc,
            toolName: "generic-signoff",
            logPath: "/tmp/generic-signoff.log",
            rawOutput: rawOutput,
            success: success
        )
    }

    @Test("An empty generic log is not accepted as completion proof")
    func emptyLogIsNotCompletionProof() {
        let result = report("")
        #expect(!result.completed)
        #expect(!result.passed)
    }

    @Test("A whitespace-only generic log is not accepted as completion proof")
    func whitespaceOnlyLogIsNotCompletionProof() {
        let result = report(" \n\t ")
        #expect(!result.completed)
        #expect(!result.passed)
    }

    @Test("A generic log with evidence remains compatible")
    func explicitPassingResultMarkerPasses() {
        let result = report("""
        [INFO] rule=GENERIC_CLEAN message="clean"
        SIGNOFF_RESULT status=pass
        """)
        #expect(result.completed)
        #expect(result.passed)
    }

    @Test("A non-empty generic log without a result marker is incomplete")
    func nonEmptyGenericLogWithoutResultMarkerIsIncomplete() {
        let result = report(#"[INFO] rule=GENERIC_CLEAN message="clean""#)
        #expect(!result.completed)
        #expect(!result.passed)
    }

    @Test("A generic failure result marker blocks pass")
    func failureResultMarkerBlocksPass() {
        let result = report("SIGNOFF_RESULT status=failed")
        #expect(result.completed)
        #expect(!result.passed)
        #expect(result.diagnostics.contains {
            $0.ruleID == "SIGNOFF_RESULT" && $0.severity == .error
        })
    }
}

/// Pure parser tests for the `.magicDRC` style — they need no Magic installation,
/// so they cover the normalization contract in CI even when the gated
/// `MagicDRCSignoffTests` integration tests are skipped.
@Suite("ExternalSignoffReportParser .magicDRC")
struct ExternalSignoffReportParserTests {
    @Test func reportArtifactRejectsMissingCompletionEvidence() throws {
        let data = Data(
            #"{"kind":"drc","toolName":"Magic","success":true,"parserStyle":"generic","logPath":"drc.log","diagnostics":[]}"#.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ExternalSignoffToolReport.self, from: data)
        }
    }


    private let parser = ExternalSignoffReportParser(style: .magicDRC)

    private func report(_ rawOutput: String, success: Bool = true) -> ExternalSignoffToolReport {
        parser.parse(
            kind: .drc,
            toolName: "magic",
            logPath: "/tmp/drc-magic.log",
            rawOutput: rawOutput,
            success: success
        )
    }

    @Test("A clean run yields no diagnostics and ignores Magic chatter")
    func cleanRunHasNoDiagnostics() {
        // Representative clean stdout: Magic banner/chatter (including the
        // substring "errors"), then the driver's normalized summary.
        let raw = """
        Magic 8.3 revision 652
        Loading sky130A Device Generator Menu ...
        No errors found.
        DRC_SUMMARY total=0 cell=sky130_fd_sc_hd__inv_1
        DRC_DONE
        """
        let result = report(raw)
        #expect(result.diagnostics.isEmpty,
                "Magic chatter must not be parsed; got \(result.diagnostics.map(\.rawLine))")
        #expect(result.passed)
    }

    @Test("A normalized VIOLATION line becomes an error diagnostic attributed to its rule")
    func violationLineParsed() {
        let raw = """
        DRC_SUMMARY total=2 cell=drc_broken
        VIOLATION rule=met1.2 count=2 message="Metal1 spacing < 0.14um (met1.2)"
        DRC_DONE
        """
        let result = report(raw)
        #expect(result.diagnostics.count == 1)
        let diagnostic = result.diagnostics.first
        #expect(diagnostic?.severity == .error)
        #expect(diagnostic?.ruleID == "met1.2")
        #expect(diagnostic?.message == "Metal1 spacing < 0.14um (met1.2)")
        #expect(!result.passed)
    }

    @Test("A driver ERROR line is reported as an error diagnostic")
    func driverErrorParsed() {
        let raw = #"ERROR rule=DRIVER message="cell not found or empty: foo""#
        let result = report(raw)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.severity == .error)
        #expect(result.diagnostics.first?.ruleID == "DRIVER")
        #expect(!result.passed)
    }

    @Test("Multiple violations across rules are each captured")
    func multipleViolations() {
        let raw = """
        DRC_SUMMARY total=3 cell=block
        VIOLATION rule=met1.2 count=2 message="Metal1 spacing < 0.14um (met1.2)"
        VIOLATION rule=poly.2 count=1 message="Poly spacing < 0.21um (poly.2)"
        DRC_DONE
        """
        let result = report(raw)
        #expect(result.diagnostics.count == 2)
        #expect(Set(result.diagnostics.compactMap(\.ruleID)) == ["met1.2", "poly.2"])
    }

    @Test("A truncated run (exit 0, no DRC_DONE) is not a false pass — completion is required")
    func truncatedRunIsNotAPass() {
        // Magic exited 0 but produced no completion marker (silent crash / lost tail).
        // Absence of VIOLATION lines must NOT be read as a clean pass.
        let raw = """
        Magic 8.3 revision 652
        Loading sky130A Device Generator Menu ...
        """
        let result = report(raw, success: true)
        #expect(!result.completed)
        #expect(!result.passed)
    }

    @Test("A marker-like token inside chatter is not completion proof")
    func markerTextInsideChatterIsNotCompletionProof() {
        let raw = """
        Magic 8.3 revision 652
        INFO message="driver did not emit DRC_DONE before output ended"
        """
        let result = report(raw, success: true)
        #expect(!result.completed)
        #expect(!result.passed)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("DRC_SUMMARY total>0 with no enumerated VIOLATION still fails (count gates the verdict)")
    func authoritativeCountGatesTheVerdict() {
        // The authoritative count says 5, but no VIOLATION line was enumerated; the
        // verdict must follow the count, not the (empty) enumeration.
        let raw = """
        DRC_SUMMARY total=5 cell=block
        DRC_DONE
        """
        let result = report(raw, success: true)
        #expect(result.completed)
        #expect(result.diagnostics.contains { $0.ruleID == "DRC_SUMMARY_MISMATCH" && $0.severity == .error })
        #expect(!result.passed)
    }
}

/// Pure parser tests for the `.netgenLVS` style — no Netgen installation needed.
@Suite("ExternalSignoffReportParser .netgenLVS")
struct NetgenLVSReportParserTests {

    private let parser = ExternalSignoffReportParser(style: .netgenLVS)

    private func report(_ rawOutput: String) -> ExternalSignoffToolReport {
        parser.parse(
            kind: .lvs,
            toolName: "netgen",
            logPath: "/tmp/lvs-netgen.log",
            rawOutput: rawOutput,
            success: true
        )
    }

    @Test("A clean match yields no diagnostics and passes")
    func cleanMatchPasses() {
        // The driver's normalized success line plus Netgen chatter.
        let raw = """
        Netgen 1.5.320
        No property mult found for device sky130_fd_pr__nfet_01v8
        LVS_RESULT status=match message="Circuits match uniquely."
        LVS_DONE
        """
        let result = report(raw)
        #expect(result.diagnostics.isEmpty,
                "no diagnostics on a clean match; got \(result.diagnostics.map(\.rawLine))")
        #expect(result.passed)
    }

    @Test("A mismatch becomes an LVS_MISMATCH error and ignores Netgen's *** MISMATCH *** chatter")
    func mismatchParsed() {
        let raw = """
        Circuit 1 contains 1 devices, Circuit 2 contains 2 devices. *** MISMATCH ***
        Circuit 1 contains 4 nets,    Circuit 2 contains 6 nets. *** MISMATCH ***
        MISMATCH rule=LVS_MISMATCH message="Top level cell failed pin matching."
        LVS_DONE
        """
        let result = report(raw)
        // Only the driver's normalized line is a diagnostic — the raw "*** MISMATCH ***"
        // count lines (no rule= field) are ignored.
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.severity == .error)
        #expect(result.diagnostics.first?.ruleID == "LVS_MISMATCH")
        #expect(result.diagnostics.first?.message == "Top level cell failed pin matching.")
        #expect(!result.passed)
    }

    @Test("A driver ERROR line is reported")
    func driverErrorParsed() {
        let result = report(#"ERROR rule=DRIVER message="setup file not found: x""#)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.ruleID == "DRIVER")
        #expect(!result.passed)
    }

    @Test("A run without the positive match marker (exit 0, truncated) is not a false pass")
    func missingMatchMarkerIsNotAPass() {
        // Netgen exited 0 and emitted no MISMATCH, but also never produced the
        // positive `LVS_RESULT status=match` line — absence of a mismatch must NOT
        // be read as a match.
        let raw = """
        Netgen 1.5.320
        Contents of circuit 1: ...
        LVS_DONE
        """
        let result = report(raw)
        #expect(!result.completed)
        #expect(!result.passed)
    }

    @Test("A marker-like token inside chatter is not a positive LVS match")
    func markerTextInsideChatterIsNotCompletionProof() {
        let raw = """
        Netgen 1.5.320
        INFO message="previous log contained LVS_RESULT status=match"
        LVS_DONE
        """
        let result = report(raw)
        #expect(!result.completed)
        #expect(!result.passed)
        #expect(result.diagnostics.isEmpty)
    }
}

/// Pure parser tests for the `.magicAntenna` style — no Magic installation needed.
@Suite("ExternalSignoffReportParser .magicAntenna")
struct MagicAntennaReportParserTests {

    private let parser = ExternalSignoffReportParser(style: .magicAntenna)

    private func report(_ rawOutput: String, success: Bool = true) -> ExternalSignoffToolReport {
        parser.parse(
            kind: .antenna,
            toolName: "magic",
            logPath: "/tmp/antenna-magic.log",
            rawOutput: rawOutput,
            success: success
        )
    }

    @Test("A clean antenna run passes with a standalone completion marker")
    func cleanRunPasses() {
        let raw = """
        ANTENNA_SUMMARY total=0 cell=ant_clean
        ANTENNA_DONE
        """
        let result = report(raw)
        #expect(result.completed)
        #expect(result.passed)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("ANTENNA_SUMMARY total>0 with no enumerated violation still fails")
    func authoritativeCountGatesTheVerdict() {
        let raw = """
        ANTENNA_SUMMARY total=2 cell=ant_violation
        ANTENNA_DONE
        """
        let result = report(raw)
        #expect(result.completed)
        #expect(result.diagnostics.contains { $0.ruleID == "ANTENNA_SUMMARY_MISMATCH" && $0.severity == .error })
        #expect(!result.passed)
    }

    @Test("A marker-like token inside chatter is not antenna completion proof")
    func markerTextInsideChatterIsNotCompletionProof() {
        let raw = """
        Magic 8.3 revision 652
        INFO message="driver did not emit ANTENNA_DONE before output ended"
        """
        let result = report(raw)
        #expect(!result.completed)
        #expect(!result.passed)
        #expect(result.diagnostics.isEmpty)
    }
}

@Suite("ExternalSignoffReportParser .calibreLike")
struct CalibreLikeReportParserTests {

    private let parser = ExternalSignoffReportParser(style: .calibreLike)

    @Test("Calibre DRC result count gates pass even when no violation line is parsed")
    func drcResultCountGatesPass() {
        let result = parser.parse(
            kind: .drc,
            toolName: "calibre",
            logPath: "/tmp/calibre-drc.log",
            rawOutput: """
            Calibre nmDRC summary
            TOTAL DRC Results Generated: 2
            """,
            success: true
        )

        #expect(result.completed)
        #expect(!result.passed)
        #expect(result.diagnostics.contains {
            $0.ruleID == "CALIBRE_DRC_RESULTS" && $0.severity == .error
        })
    }

    @Test("Calibre DRC without a result count is incomplete")
    func drcWithoutResultCountIsIncomplete() {
        let result = parser.parse(
            kind: .drc,
            toolName: "calibre",
            logPath: "/tmp/calibre-drc.log",
            rawOutput: "Calibre nmDRC summary",
            success: true
        )

        #expect(!result.completed)
        #expect(!result.passed)
    }
}
