import Foundation

/// Errors raised while validating or traversing a cell library.
public enum CellLibraryError: Error, Equatable, LocalizedError {
    /// A cell name is not a valid SPICE identifier.
    case invalidCellName(String)
    /// Two cells share the same name.
    case duplicateCellName(String)
    /// A schematic instantiates a cell that does not exist in the library.
    case unknownCellReference(parent: String, child: String)
    /// A lookup target does not exist in the library.
    case unknownCell(String)
    /// Cell instantiations form a cycle; the path lists the cells involved.
    case dependencyCycle([String])

    public var errorDescription: String? {
        switch self {
        case .invalidCellName(let name):
            return "Cell name '\(name)' is not a valid SPICE identifier (expected [A-Za-z][A-Za-z0-9_]*)."
        case .duplicateCellName(let name):
            return "Duplicate cell name '\(name)'. Cell names must be unique within a project."
        case .unknownCellReference(let parent, let child):
            return "Cell '\(parent)' instantiates '\(child)', which does not exist in the project."
        case .unknownCell(let name):
            return "Cell '\(name)' does not exist in the project."
        case .dependencyCycle(let path):
            return "Cell instantiation cycle: \(path.joined(separator: " → "))."
        }
    }
}

/// The set of cells that make up a project, with one designated top cell.
///
/// Cells reference each other by name through placed cell instances
/// (`PlacedComponent.cellName`). The library is the unit the netlist
/// generator, the palette catalog, and project persistence all consume.
public struct CellLibrary: Sendable {
    public var cells: [DesignCell]
    public var topCellName: String?

    public init(cells: [DesignCell] = [], topCellName: String? = nil) {
        self.cells = cells
        self.topCellName = topCellName
    }

    /// Case-folded identity key for a cell name. SPICE subcircuit names are
    /// case-insensitive, and the on-disk `cells/<name>/` directory lives on a
    /// case-insensitive file system, so "INV" and "inv" denote one cell.
    public static func identityKey(_ name: String) -> String {
        name.lowercased()
    }

    public func cell(named name: String) -> DesignCell? {
        let key = Self.identityKey(name)
        return cells.first { Self.identityKey($0.name) == key }
    }

    public var cellNames: [String] {
        cells.map(\.name)
    }

    /// Validates names, reference resolution, and acyclicity.
    public func validate() throws {
        var seen: Set<String> = []
        for cell in cells {
            guard CellInterface.isValidSPICEName(cell.name) else {
                throw CellLibraryError.invalidCellName(cell.name)
            }
            guard seen.insert(Self.identityKey(cell.name)).inserted else {
                throw CellLibraryError.duplicateCellName(cell.name)
            }
        }
        for cell in cells {
            for child in cell.referencedCellNames where self.cell(named: child) == nil {
                throw CellLibraryError.unknownCellReference(parent: cell.name, child: child)
            }
        }
        for cell in cells {
            _ = try orderedDependencies(of: cell.name)
        }
    }

    /// All cells `name` transitively instantiates, deepest-first, excluding
    /// `name` itself — the emission order for `.subckt` definitions.
    ///
    /// Throws on unresolved references and cycles.
    public func orderedDependencies(of name: String) throws -> [String] {
        guard cell(named: name) != nil else {
            throw CellLibraryError.unknownCell(name)
        }
        var ordered: [String] = []
        var visited: Set<String> = []
        var stack: [String] = []

        func visit(_ current: String) throws {
            let key = Self.identityKey(current)
            if let cycleStart = stack.firstIndex(where: { Self.identityKey($0) == key }) {
                throw CellLibraryError.dependencyCycle(Array(stack[cycleStart...]) + [current])
            }
            if visited.contains(key) { return }
            guard let cell = cell(named: current) else {
                let parent = stack.last ?? name
                throw CellLibraryError.unknownCellReference(parent: parent, child: current)
            }
            // Record the canonical defined name, not the reference spelling,
            // so emission order and cycle paths stay independent of how a
            // parent happened to capitalize the instance's cell name.
            stack.append(cell.name)
            for child in cell.referencedCellNames {
                try visit(child)
            }
            stack.removeLast()
            visited.insert(key)
            ordered.append(cell.name)
        }

        try visit(name)
        // The root itself is last in post-order; dependencies exclude it.
        return ordered.dropLast()
    }

    /// True when `candidate` is `target` or transitively instantiates it —
    /// placing `candidate` inside `target` would then create a cycle.
    public func reaches(from candidate: String, to target: String) -> Bool {
        let targetKey = Self.identityKey(target)
        var visited: Set<String> = []
        var queue: [String] = [candidate]
        while let current = queue.popLast() {
            let key = Self.identityKey(current)
            guard visited.insert(key).inserted else { continue }
            if key == targetKey { return true }
            guard let cell = cell(named: current) else { continue }
            queue.append(contentsOf: cell.referencedCellNames)
        }
        return false
    }
}
