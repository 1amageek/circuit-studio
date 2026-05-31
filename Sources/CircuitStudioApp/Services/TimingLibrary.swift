import Foundation

/// A timing library: the NLDM model for every combinational cell used by a design plus the
/// flip-flop model — the standard-cell `.lib` (a Liberty subset) the static timing analyzer
/// reads. It is produced by `CellTimingCharacterizer` (SPICE) and validated against full
/// SPICE by `STAvsSPICEValidator`, so the abstraction the STA trusts is itself checked
/// against physics rather than assumed.
public struct TimingLibrary: Sendable, Hashable, Codable {

    public enum LibraryError: Error, LocalizedError, Equatable {
        case missingCell(String)
        case missingArc(cell: String, input: String)
        case noSequentialModel

        public var errorDescription: String? {
            switch self {
            case .missingCell(let c): return "Timing library has no model for cell '\(c)'."
            case .missingArc(let c, let i): return "Cell '\(c)' has no timing arc from input '\(i)'."
            case .noSequentialModel: return "Timing library has no flip-flop (sequential) model."
            }
        }
    }

    public var cells: [String: CellTiming]
    public var flipFlop: SequentialTiming?

    public init(cells: [String: CellTiming] = [:], flipFlop: SequentialTiming? = nil) {
        self.cells = cells
        self.flipFlop = flipFlop
    }

    public func cell(_ name: String) throws -> CellTiming {
        guard let c = cells[name] else { throw LibraryError.missingCell(name) }
        return c
    }

    public func sequential() throws -> SequentialTiming {
        guard let ff = flipFlop else { throw LibraryError.noSequentialModel }
        return ff
    }

    public mutating func add(_ cell: CellTiming) { cells[cell.cellName] = cell }
}
