import Foundation
import Testing
@testable import CircuitStudioApp

/// Tool-independent tests for the circuit LOADERS — a circuit/logic is data parsed from
/// text, not hardcoded in Swift. These run everywhere (no Magic/Netgen needed).
@Suite("Circuit loaders (structural Verilog + Boolean expression)")
struct CircuitLoaderTests {

    @Test("Structural Verilog parses into the expected gate-level netlist")
    func parsesStructuralVerilog() throws {
        let verilog = """
        module aoi (a, b, c, y);
          input a, b, c;
          output y;
          nand2 g0 ( .A(a), .B(b), .Y(t1) );
          inv   g1 ( .A(t1), .Y(ab) );
          nor2  g2 ( .A(ab), .B(c), .Y(t2) );
          inv   g3 ( .A(t2), .Y(y) );
        endmodule
        """
        let n = try VerilogStructuralParser().parse(verilog)
        let output = try n.requirePrimaryOutput()
        #expect(n.name == "aoi")
        #expect(n.inputs.sorted() == ["a", "b", "c"])
        #expect(output == "y")
        #expect(n.instances.count == 4)
        let g2 = try #require(n.instances.first { $0.name == "g2" })
        #expect(g2.cell.devices.count == 4)               // NOR2 = 4 FETs
        #expect(g2.net("A") == "ab")                      // connection by name
        #expect(g2.net("B") == "c")
        #expect(g2.net("Y") == "t2")
    }

    @Test("An unknown cell type fails loud")
    func unknownCellFailsLoud() {
        let verilog = "module m(a,y); input a; output y; xor2 g(.A(a),.B(a),.Y(y)); endmodule"
        #expect(throws: VerilogStructuralParser.ParseError.unknownCell("xor2")) {
            _ = try VerilogStructuralParser().parse(verilog)
        }
    }

    @Test("A Boolean expression parses with correct precedence (~ , & , |)")
    func parsesBooleanExpression() throws {
        // ~a | b & c  ==  (~a) | (b & c)
        let expr = try BooleanExpressionParser().parse("y = ~a | b & c")
        #expect(expr == .or(.not(.input("a")), .and(.input("b"), .input("c"))))
    }

    @Test("A Boolean expression maps to a gate-level netlist with the right inputs/output")
    func mapsBooleanToNetlist() throws {
        let n = try BooleanExpressionParser().netlist("(a & b) | c", name: "expr", output: "out")
        let output = try n.requirePrimaryOutput()
        #expect(n.inputs.sorted() == ["a", "b", "c"])
        #expect(output == "out")
        // AND -> NAND2+INV, OR -> NOR2+INV  => 4 cells.
        #expect(n.instances.count == 4)
    }

    @Test("A gate-level netlist without outputs fails as typed validation error")
    func missingPrimaryOutputFailsWithTypedError() {
        let n = GateLevelNetlist(name: "invalid", instances: [], inputs: ["a"], outputs: [])
        #expect(throws: GateLevelNetlist.ValidationError.missingOutput(netlistName: "invalid")) {
            _ = try n.requirePrimaryOutput()
        }
    }

    @Test("A malformed Boolean expression fails loud")
    func malformedBooleanFailsLoud() {
        #expect(throws: (any Error).self) {
            _ = try BooleanExpressionParser().parse("a & (b | )")
        }
    }
}
