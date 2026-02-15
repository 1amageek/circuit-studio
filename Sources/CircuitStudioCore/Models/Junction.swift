import Foundation
import CoreGraphics

/// A junction point where three or more wires meet on the schematic.
public struct Junction: Sendable, Identifiable, Codable {
    public let id: UUID
    public var position: CGPoint

    public init(id: UUID = UUID(), position: CGPoint) {
        self.id = id
        self.position = position
    }
}
