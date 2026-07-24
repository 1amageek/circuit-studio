import Foundation
import LayoutCore

struct LayoutTopologyValidator: Sendable {
    func validate(layout: LayoutDocument, topCell: LayoutCell?) -> [String] {
        guard let topCell else {
            return ["Missing top cell"]
        }
        let cellIDs = Set(layout.cells.map(\.id))
        var errors: [String] = []
        for cell in layout.cells {
            for instance in cell.instances where !cellIDs.contains(instance.cellID) {
                errors.append("Missing referenced cell '\(instance.cellID.uuidString)' from instance '\(instance.name)' in cell '\(cell.name)'")
            }
        }

        var visiting: [UUID] = []
        var visited = Set<UUID>()
        detectCycles(
            layout: layout,
            cell: topCell,
            visiting: &visiting,
            visited: &visited,
            errors: &errors
        )
        return Array(Set(errors)).sorted()
    }

    private func detectCycles(
        layout: LayoutDocument,
        cell: LayoutCell,
        visiting: inout [UUID],
        visited: inout Set<UUID>,
        errors: inout [String]
    ) {
        if let cycleStart = visiting.firstIndex(of: cell.id) {
            let cycleIDs = visiting[cycleStart...] + [cell.id]
            let names = cycleIDs.map { layout.cell(withID: $0)?.name ?? $0.uuidString }
            errors.append("Hierarchy cycle: \(names.joined(separator: " -> "))")
            return
        }
        guard !visited.contains(cell.id) else { return }
        visiting.append(cell.id)
        for instance in cell.instances {
            guard let child = layout.cell(withID: instance.cellID) else { continue }
            detectCycles(
                layout: layout,
                cell: child,
                visiting: &visiting,
                visited: &visited,
                errors: &errors
            )
        }
        _ = visiting.popLast()
        visited.insert(cell.id)
    }
}
