import Foundation
import CoreGraphics

/// Builds the schematic symbol for a cell instance from its interface:
/// a box with inputs on the left, outputs and bidirectional ports on the
/// right, power on top, and ground on the bottom.
public enum CellSymbolFactory {

    private static let pinPitch: CGFloat = 20
    private static let pinStub: CGFloat = 10
    private static let minBodyWidth: CGFloat = 60
    private static let minBodyHeight: CGFloat = 40

    /// Symbol geometry and port definitions, in symbol-local coordinates
    /// centered on the body.
    public static func make(
        cellName: String,
        interface: CellInterface
    ) -> (symbol: SymbolDefinition, portDefinitions: [PortDefinition]) {
        let leftPorts = interface.ports.filter { $0.direction == .input }
        let rightPorts = interface.ports.filter {
            $0.direction == .output || $0.direction == .bidirectional
        }
        let topPorts = interface.ports.filter { $0.direction == .power }
        let bottomPorts = interface.ports.filter { $0.direction == .ground }

        let sideRows = max(leftPorts.count, rightPorts.count)
        let bodyHeight = max(minBodyHeight, CGFloat(sideRows + 1) * pinPitch)
        let verticalColumns = max(topPorts.count, bottomPorts.count)
        let bodyWidth = max(minBodyWidth, CGFloat(verticalColumns + 1) * pinPitch)

        let halfW = bodyWidth / 2
        let halfH = bodyHeight / 2

        var commands: [DrawCommand] = [
            .rect(origin: CGPoint(x: -halfW, y: -halfH), size: CGSize(width: bodyWidth, height: bodyHeight)),
            .text(cellName, at: CGPoint(x: 0, y: 0), fontSize: 10),
        ]
        var portDefinitions: [PortDefinition] = []

        func sideY(row: Int, count: Int) -> CGFloat {
            // Rows centered vertically inside the body.
            let span = CGFloat(count - 1) * pinPitch
            return -span / 2 + CGFloat(row) * pinPitch
        }

        func columnX(column: Int, count: Int) -> CGFloat {
            let span = CGFloat(count - 1) * pinPitch
            return -span / 2 + CGFloat(column) * pinPitch
        }

        for (row, port) in leftPorts.enumerated() {
            let y = sideY(row: row, count: leftPorts.count)
            let pin = CGPoint(x: -halfW - pinStub, y: y)
            commands.append(.line(from: pin, to: CGPoint(x: -halfW, y: y)))
            commands.append(.text(port.name, at: CGPoint(x: -halfW + 4, y: y), fontSize: 7))
            portDefinitions.append(PortDefinition(id: port.id, displayName: port.name, position: pin))
        }

        for (row, port) in rightPorts.enumerated() {
            let y = sideY(row: row, count: rightPorts.count)
            let pin = CGPoint(x: halfW + pinStub, y: y)
            commands.append(.line(from: CGPoint(x: halfW, y: y), to: pin))
            commands.append(.text(port.name, at: CGPoint(x: halfW - 4, y: y), fontSize: 7))
            portDefinitions.append(PortDefinition(id: port.id, displayName: port.name, position: pin))
        }

        for (column, port) in topPorts.enumerated() {
            let x = columnX(column: column, count: topPorts.count)
            let pin = CGPoint(x: x, y: -halfH - pinStub)
            commands.append(.line(from: pin, to: CGPoint(x: x, y: -halfH)))
            commands.append(.text(port.name, at: CGPoint(x: x, y: -halfH + 8), fontSize: 7))
            portDefinitions.append(PortDefinition(id: port.id, displayName: port.name, position: pin))
        }

        for (column, port) in bottomPorts.enumerated() {
            let x = columnX(column: column, count: bottomPorts.count)
            let pin = CGPoint(x: x, y: halfH + pinStub)
            commands.append(.line(from: CGPoint(x: x, y: halfH), to: pin))
            commands.append(.text(port.name, at: CGPoint(x: x, y: halfH - 8), fontSize: 7))
            portDefinitions.append(PortDefinition(id: port.id, displayName: port.name, position: pin))
        }

        let symbol = SymbolDefinition(
            shape: .custom(commands),
            size: CGSize(width: bodyWidth + 2 * pinStub, height: bodyHeight + 2 * pinStub),
            iconName: "cpu"
        )
        return (symbol, portDefinitions)
    }
}
