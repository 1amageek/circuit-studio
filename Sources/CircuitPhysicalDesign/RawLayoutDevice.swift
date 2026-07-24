struct RawLayoutDevice: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case nmos
        case pmos
        case resistor
        case capacitor

        var numericValue: Double {
            switch self {
            case .nmos: return 0
            case .pmos: return 1
            case .resistor: return 2
            case .capacitor: return 3
            }
        }
    }

    let name: String
    let kind: Kind
    let width: Double
    let length: Double
    let fingerCount: Int
    let resistance: Double?
    let capacitance: Double?
    let terminals: [RawLayoutTerminal]
}
