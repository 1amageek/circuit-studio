import Foundation
import Testing
@testable import CircuitStudioApp

/// Pure parser tests for the `.magicDRC` style — they need no Magic installation,
/// so they cover the normalization contract in CI even when the gated
/// `MagicDRCSignoffTests` integration tests are skipped.
@Suite("ExternalSignoffReportParser .magicDRC")
struct ExternalSignoffReportParserTests {

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
}
