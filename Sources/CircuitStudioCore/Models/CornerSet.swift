import Foundation

/// PVT (Process/Voltage/Temperature) conditions for corner analysis.
public struct CornerSet: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var corners: [Corner]

    public init(id: UUID = UUID(), name: String, corners: [Corner] = []) {
        self.id = id
        self.name = name
        self.corners = corners
    }
}

/// A single PVT corner.
public struct Corner: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var temperature: Double
    public var parameterOverrides: [String: Double]
    public var librarySectionOverrides: [String: String]

    public init(
        id: UUID = UUID(),
        name: String,
        temperature: Double = 27.0,
        parameterOverrides: [String: Double] = [:],
        librarySectionOverrides: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.temperature = temperature
        self.parameterOverrides = parameterOverrides
        self.librarySectionOverrides = librarySectionOverrides
    }
}
