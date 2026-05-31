import Foundation
import Testing
@testable import CircuitStudioApp

/// BC1.1 — the NLDM lookup table: bilinear interpolation inside the grid and linear
/// extrapolation past its edges (not a silent clamp), so STA stays defined off-grid.
@Suite("Timing LUT (NLDM)")
struct TimingLUTTests {

    @Test("Bilinear interpolation hits the corners and the centre exactly")
    func bilinearInterpolation() throws {
        let lut = try TimingLUT(inputSlews: [1e-12, 2e-12], outputLoads: [1e-15, 3e-15],
                                values: [[10, 20], [30, 40]])
        #expect(lut.lookup(inputSlew: 1e-12, outputLoad: 1e-15) == 10)   // corner
        #expect(lut.lookup(inputSlew: 2e-12, outputLoad: 3e-15) == 40)   // corner
        #expect(abs(lut.lookup(inputSlew: 1.5e-12, outputLoad: 2e-15) - 25) < 1e-9)  // centre = mean
    }

    @Test("Off-grid queries extrapolate linearly from the edge samples")
    func extrapolation() throws {
        let lut = try TimingLUT(inputSlews: [1e-12, 2e-12], outputLoads: [1e-15, 3e-15],
                                values: [[10, 20], [30, 40]])
        // slew = 3e-12 is one step beyond the top row: frac = 2 along the slew axis at load col0.
        #expect(abs(lut.lookup(inputSlew: 3e-12, outputLoad: 1e-15) - 50) < 1e-9)   // 10 + (30-10)*2
    }

    @Test("A one-sample axis is constant along that dimension")
    func constantTable() {
        let lut = TimingLUT.constant(42)
        #expect(lut.lookup(inputSlew: 0, outputLoad: 0) == 42)
        #expect(lut.lookup(inputSlew: 5e-12, outputLoad: 9e-15) == 42)
    }

    @Test("A shape mismatch is rejected at construction (never silently)")
    func shapeMismatchRejected() {
        #expect(throws: TimingLUT.LUTError.self) {
            _ = try TimingLUT(inputSlews: [1e-12, 2e-12], outputLoads: [1e-15], values: [[1]])
        }
    }
}
