import Foundation
import CircuitStudioCore
import CoreSpiceWaveform

/// The full Spec → GDS chain: size a CMOS inverter electrically to meet a performance
/// spec (against the ngspice-validated Measure stage), then synthesize the SIZED
/// device as a Sky130 cell and sign it off with real Magic DRC + Netgen LVS.
///
/// This is the bridge between the two axes of the agent loop:
///   electrical (`SpecDrivenDesignLoop` sizes W in metres against a delay target)
///   physical   (`Sky130CellSignoffService` builds the cell at W µm and signs it off).
/// The agent states an electrical intent and gets back a physically signed-off GDS
/// that realises it — not a hand-picked geometry.
///
/// Two honest modelling boundaries are crossed and reported, never hidden:
///  - the loop sizes W in metres; the layout is built in µm (`× 1e6`);
///  - the electrical optimum may fall below the Sky130 minimum device width, in which
///    case the layout is built at the floor and `widthClampedToFloor` is set true.
/// The width is snapped UP to the Sky130 manufacturing grid so the realised cell is
/// never narrower than the sized device (it can only be as fast or faster).
public struct SpecDrivenCellFlow: Sendable {

    /// The Sky130 manufacturing grid (µm); layout coordinates must land on it.
    public static let gridMicrons = 0.005

    public struct Output: Sendable {
        /// The electrical sizing result — the loop that chose W.
        public let electrical: SpecDrivenDesignLoop.Outcome
        /// The transistor width the layout was actually built at (µm, grid-snapped).
        public let layoutWidthMicrons: Double
        /// The width the electrical loop converged on (µm, before flooring/snapping).
        public let sizedWidthMicrons: Double
        /// True when the electrical optimum was below the Sky130 minimum width and the
        /// layout width was raised to the floor (the physical constraint dominated).
        public let widthClampedToFloor: Bool
        /// The physical signoff: emitted GDS + real DRC + LVS review.
        public let physical: Sky130CellSignoffService.Output

        public var converged: Bool { electrical.converged }
        public var passed: Bool { physical.passed }
    }

    public enum FlowError: Error, LocalizedError, Equatable {
        case electricalDidNotConverge(iterations: Int)
        case noSizingProduced

        public var errorDescription: String? {
            switch self {
            case .electricalDidNotConverge(let n):
                return "Electrical sizing did not meet the spec in \(n) iterations; refusing to synthesize a cell that misses its spec."
            case .noSizingProduced:
                return "The electrical loop converged but produced no sized parameter value."
            }
        }
    }

    private let loop: SpecDrivenDesignLoop
    private let signoff: Sky130CellSignoffService

    public init(loop: SpecDrivenDesignLoop = SpecDrivenDesignLoop(), signoff: Sky130CellSignoffService) {
        self.loop = loop
        self.signoff = signoff
    }

    /// Available only with the real Magic + Netgen + Sky130 toolchain.
    public static func locate(
        loop: SpecDrivenDesignLoop = SpecDrivenDesignLoop(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> SpecDrivenCellFlow? {
        Sky130CellSignoffService.locate(environment: environment, fileManager: fileManager)
            .map { SpecDrivenCellFlow(loop: loop, signoff: $0) }
    }

    /// Size the inverter electrically to meet `spec`, then synthesize and sign off the
    /// sized cell. Throws (never silently degrades) if the loop fails to meet the spec.
    public func run(
        initial: DesignFlowDesignSpec,
        tunable: SpecDrivenDesignLoop.Tunable,
        spec: PerformanceSpec,
        maxIterations: Int,
        cellName: String = "sky130_inverter",
        into directory: URL,
        measure: @Sendable @escaping (WaveformData) throws -> Double
    ) async throws -> Output {
        let outcome = try await loop.run(
            initial: initial, tunable: tunable, spec: spec,
            maxIterations: maxIterations, measure: measure
        )
        guard outcome.converged else {
            throw FlowError.electricalDidNotConverge(iterations: outcome.iterations.count)
        }
        guard let sizedMetres = outcome.iterations.last?.parameterValue else {
            throw FlowError.noSizingProduced
        }

        // Cross the metre → µm boundary, apply the physical floor, snap UP to grid so
        // the realised device is never narrower than the sized one.
        let sizedMicrons = sizedMetres * 1e6
        let floored = max(Sky130InverterGenerator.minWidth, sizedMicrons)
        let clamped = floored > sizedMicrons + 1e-9
        let widthMicrons = (floored / Self.gridMicrons).rounded(.up) * Self.gridMicrons

        let physical = try await signoff.synthesizeInverter(
            name: cellName, width: widthMicrons, into: directory
        )
        return Output(
            electrical: outcome,
            layoutWidthMicrons: widthMicrons,
            sizedWidthMicrons: sizedMicrons,
            widthClampedToFloor: clamped,
            physical: physical
        )
    }
}
