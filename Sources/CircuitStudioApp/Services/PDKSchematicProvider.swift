import Foundation

/// Derives a standard cell's reference schematic netlist (its `.subckt` block)
/// from the installed PDK, so a design referenced by cell name can be signed off
/// without a hand-supplied schematic — the PDK already ships it.
///
/// The library is inferred from the cell-name prefix (`sky130_fd_sc_hd__inv_1`
/// → `sky130_fd_sc_hd`), and the subckt is sliced from that library's merged
/// SPICE deck.
public struct PDKSchematicProvider: Sendable {

    public let pdkRoot: String

    public init(pdkRoot: String) {
        self.pdkRoot = pdkRoot
    }

    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> PDKSchematicProvider? {
        Sky130PDK.root(environment: environment, fileManager: fileManager).map(PDKSchematicProvider.init(pdkRoot:))
    }

    /// The standard-cell library used to probe PDK readiness (`signoff doctor`).
    public static let representativeLibrary = "sky130_fd_sc_hd"

    /// Whether the PDK actually ships the standard-cell SPICE deck a `check --cell`
    /// run needs to derive a reference schematic. `locate()` only proves the PDK
    /// root exists; this proves the deck a design-by-name needs is present, so
    /// `doctor` does not report Ready while `check --cell` would fail at runtime.
    public func hasLibraryDeck(
        library: String = PDKSchematicProvider.representativeLibrary,
        fileManager: FileManager = .default
    ) -> Bool {
        let deckURL = URL(filePath: pdkRoot)
            .appending(path: "sky130A/libs.ref/\(library)/spice/\(library).spice")
        return fileManager.fileExists(atPath: deckURL.path(percentEncoded: false))
    }

    public enum SchematicError: Error, LocalizedError, Equatable {
        case unrecognizedCellName(String)
        case libraryDeckMissing(String)
        case subcircuitNotFound(cell: String, deck: String)

        public var errorDescription: String? {
            switch self {
            case .unrecognizedCellName(let cell):
                return "Cannot infer the PDK library from cell name '\(cell)' (expected '<lib>__<cell>')."
            case .libraryDeckMissing(let path):
                return "PDK SPICE deck not found: \(path)"
            case .subcircuitNotFound(let cell, let deck):
                return "No .subckt '\(cell)' found in \(deck)"
            }
        }
    }

    /// Writes `cell`'s `.subckt` block to a `.spice` file under `directory` and
    /// returns its URL. Throws if the library/deck/subckt cannot be resolved —
    /// never returns an empty or wrong netlist silently.
    public func schematic(forCell cell: String, into directory: URL) throws -> URL {
        guard let separator = cell.range(of: "__") else {
            throw SchematicError.unrecognizedCellName(cell)
        }
        let library = String(cell[cell.startIndex..<separator.lowerBound])
        let deckURL = URL(filePath: pdkRoot)
            .appending(path: "sky130A/libs.ref/\(library)/spice/\(library).spice")
        guard FileManager.default.fileExists(atPath: deckURL.path(percentEncoded: false)) else {
            throw SchematicError.libraryDeckMissing(deckURL.path(percentEncoded: false))
        }

        let deck = try String(contentsOf: deckURL, encoding: .utf8)
        guard let subckt = Self.sliceSubcircuit(named: cell, from: deck) else {
            throw SchematicError.subcircuitNotFound(cell: cell, deck: deckURL.lastPathComponent)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appending(path: "\(cell).schematic.spice")
        try Data(subckt.utf8).write(to: outputURL)
        return outputURL
    }

    /// Extracts the `.subckt <cell> ... .ends` block (case-insensitive on the
    /// directives, exact on the cell name token).
    static func sliceSubcircuit(named cell: String, from deck: String) -> String? {
        var lines: [String] = []
        var inside = false
        for line in deck.split(whereSeparator: \.isNewline).map(String.init) {
            let lower = line.lowercased()
            if !inside {
                if lower.hasPrefix(".subckt") {
                    let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
                    if tokens.count >= 2, tokens[1] == cell {
                        inside = true
                        lines.append(line)
                    }
                }
            } else {
                lines.append(line)
                if lower.hasPrefix(".ends") { break }
            }
        }
        guard inside, lines.last?.lowercased().hasPrefix(".ends") == true else { return nil }
        return lines.joined(separator: "\n") + "\n"
    }
}
