import Foundation
import LayoutCore

public struct ProfiledStandardCellGenerator: StandardCellGenerator {
    public enum GeneratorError: Error, Sendable, Hashable, LocalizedError {
        case missingFixedCell(String)

        public var errorDescription: String? {
            switch self {
            case .missingFixedCell(let cellID):
                return "The standard-cell layout profile does not contain fixed cell '\(cellID)'."
            }
        }
    }

    private let cellID: String
    private let profile: StandardCellLayoutProfile

    public init(cellID: String, profile: StandardCellLayoutProfile) {
        self.cellID = cellID
        self.profile = profile
    }

    public func generate(name: String) throws -> LayoutDocument {
        try generate(name: Optional(name))
    }

    public func schematic(name: String) throws -> String {
        try schematic(name: Optional(name))
    }

    public func generate(name: String? = nil) throws -> LayoutDocument {
        let cellProfile = try fixedCell()
        let cellName = name ?? cellProfile.defaultName
        var cell = LayoutCell(
            name: cellName,
            shapes: cellProfile.shapes.map { shape in
                let layer = profile.layerReference(for: shape.layer)
                return LayoutShape(
                    layer: LayoutLayerID(name: layer.name, purpose: layer.purpose),
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: shape.rect.x, y: shape.rect.y),
                        size: LayoutSize(width: shape.rect.width, height: shape.rect.height)
                    ))
                )
            }
        )
        cell.labels = cellProfile.labels.map { label in
            let layer = profile.labelLayerReference(for: label.layer)
            return LayoutLabel(
                text: label.text,
                position: LayoutPoint(x: label.x, y: label.y),
                layer: LayoutLayerID(name: layer.name, purpose: layer.purpose)
            )
        }
        return LayoutDocument(name: cellName, cells: [cell], topCellID: cell.id)
    }

    public func schematic(name: String? = nil) throws -> String {
        let cellProfile = try fixedCell()
        let cellName = name ?? cellProfile.defaultName
        var lines = [
            cellProfile.comment,
            ".subckt \(cellName) \(cellProfile.ports.joined(separator: " "))",
        ]
        for device in cellProfile.devices {
            lines.append(deviceLine(device))
        }
        lines.append(".ends")
        return lines.joined(separator: "\n")
    }

    private func fixedCell() throws -> StandardCellLayoutProfile.FixedCellLayout {
        guard let cell = profile.fixedCells[cellID] else {
            throw GeneratorError.missingFixedCell(cellID)
        }
        return cell
    }

    private func deviceLine(_ device: StandardCellLayoutProfile.FixedCellDevice) -> String {
        let model: String
        switch device.kind {
        case .nmos:
            model = profile.deviceModels.nmos
        case .pmos:
            model = profile.deviceModels.pmos
        }
        return "\(device.instanceName) \(device.drain) \(device.gate) \(device.source) \(device.bulk) "
            + "\(model) w=\(Self.format(device.width)) l=\(Self.format(device.length))"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%g", value)
    }
}
