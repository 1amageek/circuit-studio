import Foundation

/// Typed errors for Circuit Studio operations.
public enum StudioError: Error, Sendable {
    // Parsing
    case parseFailure(String)
    case loweringFailure(String)

    // Compilation
    case compilationFailure(String)
    case deviceBindingFailure(String)

    // Simulation
    case simulationFailure(String)
    case convergenceFailure(String)
    case cancelled

    // Design
    case designNotFound(UUID)
    case testbenchNotFound(UUID)
    case experimentNotFound(UUID)
    case invalidDesign(String)

    // I/O
    case fileNotFound(String)
    case fileReadError(String)
    case exportFailure(String)
}

extension StudioError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .parseFailure(let msg): return "Parse error: \(msg)"
        case .loweringFailure(let msg): return "Lowering error: \(msg)"
        case .compilationFailure(let msg): return "Compilation error: \(msg)"
        case .deviceBindingFailure(let msg): return "Device binding error: \(msg)"
        case .simulationFailure(let msg): return "Simulation error: \(msg)"
        case .convergenceFailure(let msg): return "Convergence failure: \(msg)"
        case .cancelled: return "Simulation cancelled"
        case .designNotFound(let id): return "Design not found: \(id)"
        case .testbenchNotFound(let id): return "Testbench not found: \(id)"
        case .experimentNotFound(let id): return "Experiment not found: \(id)"
        case .invalidDesign(let msg): return "Invalid design: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .fileReadError(let msg): return "File read error: \(msg)"
        case .exportFailure(let msg): return "Export error: \(msg)"
        }
    }
}
