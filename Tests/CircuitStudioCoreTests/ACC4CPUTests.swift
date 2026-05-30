import Foundation
import Testing
@testable import CircuitStudioApp

/// M4 — the ACC-4 CPU. Tool-independent functional verification: a Fibonacci program (DATA,
/// parsed from assembly text) executes on the GATE-LEVEL core, and its (PC, ACC) trace must
/// match the independent reference interpreter, whose memory stores are in turn checked
/// against the mathematically-defined Fibonacci sequence mod 16.
@Suite("ACC-4 CPU")
struct ACC4CPUTests {

    /// Fibonacci: M0, M1 seed 1,1; each loop writes M2 = M0 + M1 then shifts the window.
    /// The stream of values stored to M2 is the Fibonacci sequence (from the 3rd term).
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

    private func fibMod16(_ count: Int) -> [Int] {
        var a = 1, b = 1, out: [Int] = []
        for _ in 0..<count { out.append(a); (a, b) = (b, (a + b) & 0xF) }
        return out
    }

    @Test("The assembler resolves labels and packs the ISA encoding")
    func assembles() throws {
        let program = try ACC4Assembler().assemble(Self.fibonacci)
        #expect(program.count == 11)
        #expect(program[0] == ACC4Instruction(.ldi, 1))
        #expect(program[3] == ACC4Instruction(.lda, 0))
        #expect(program.last == ACC4Instruction(.jmp, 3))   // `loop` resolves to address 3
        #expect(program[0].word == (1 << 4) | 1)
    }

    @Test("The reference interpreter computes Fibonacci mod 16")
    func referenceRunsFibonacci() throws {
        let program = try ACC4Assembler().assemble(Self.fibonacci)
        let result = ACC4Reference().run(program, cycles: 130)
        let m2 = result.stores.filter { $0.address == 2 }.map(\.value)
        #expect(!m2.isEmpty)
        // M2 stores are fib(2), fib(3), ... — the sequence from its third term.
        let expected = Array(fibMod16(m2.count + 2).dropFirst(2))
        #expect(m2 == expected, "M2 stores \(m2) != Fibonacci \(expected)")
    }

    @Test("The gate-level CPU core matches the reference trace executing Fibonacci")
    func gateCPUMatchesReference() throws {
        let program = try ACC4Assembler().assemble(Self.fibonacci)
        let cycles = 130
        let golden = ACC4Reference().run(program, cycles: cycles).trace
        let actual = try ACC4Machine().run(program, cycles: cycles)
        #expect(actual == golden, "gate trace diverges from the reference")
        // And the accumulator actually takes on the Fibonacci values (post-ADD ACC).
        let accValues = Set(actual.map(\.acc))
        #expect(fibMod16(12).allSatisfy { accValues.contains($0) })
    }
}
