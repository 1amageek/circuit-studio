import Foundation

/// Errors raised by multi-cell session operations.
public enum StudioSessionError: Error, Equatable, LocalizedError {
    /// The proposed cell name is not a valid SPICE identifier.
    case invalidCellName(String)
    /// A cell with the same name (case-insensitive — SPICE identifiers and
    /// the default file system both ignore case) already exists.
    case duplicateCellName(String)
    /// No cell with this name exists in the session.
    case unknownCell(String)
    /// The cell is instantiated by other cells and cannot be removed.
    case cellInUse(cell: String, referencedBy: [String])
    /// The top cell cannot be removed; designate another top cell first.
    case cannotRemoveTopCell(String)
    /// A project must keep at least one cell.
    case cannotRemoveLastCell

    public var errorDescription: String? {
        switch self {
        case .invalidCellName(let name):
            return "'\(name)' is not a valid cell name. Use a letter followed by letters, digits, or underscores."
        case .duplicateCellName(let name):
            return "A cell named '\(name)' already exists. Cell names must be unique within a project."
        case .unknownCell(let name):
            return "Cell '\(name)' does not exist in this project."
        case .cellInUse(let cell, let referencedBy):
            return "Cell '\(cell)' is instantiated by \(referencedBy.joined(separator: ", ")) and cannot be deleted. Remove those instances first."
        case .cannotRemoveTopCell(let name):
            return "Cell '\(name)' is the top cell. Set another cell as top before deleting it."
        case .cannotRemoveLastCell:
            return "A project must contain at least one cell."
        }
    }
}
