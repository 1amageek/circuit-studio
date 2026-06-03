import Foundation

public struct AntennaProtectionCandidate: Sendable, Hashable, Codable {
    public let id: String
    public let net: String
    public let instanceName: String
    public let gateName: String
    public let centerXMicrons: Double
    public let trackYMicrons: Double
    public let gateLoadCount: Int
    public let hasDiffusionDischargeAnchor: Bool
    public let spanMicrons: Double
    public let spanPerGateMicrons: Double

    public init(
        id: String,
        net: String,
        instanceName: String,
        gateName: String,
        centerXMicrons: Double,
        trackYMicrons: Double,
        gateLoadCount: Int,
        hasDiffusionDischargeAnchor: Bool,
        spanMicrons: Double,
        spanPerGateMicrons: Double
    ) {
        self.id = id
        self.net = net
        self.instanceName = instanceName
        self.gateName = gateName
        self.centerXMicrons = centerXMicrons
        self.trackYMicrons = trackYMicrons
        self.gateLoadCount = gateLoadCount
        self.hasDiffusionDischargeAnchor = hasDiffusionDischargeAnchor
        self.spanMicrons = spanMicrons
        self.spanPerGateMicrons = spanPerGateMicrons
    }
}
