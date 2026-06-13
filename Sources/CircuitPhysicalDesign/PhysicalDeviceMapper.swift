import CircuitStudioCore
import LayoutAutoGen

public enum PhysicalDeviceMapper {
    static func canonicalDeviceKindID(_ kind: DeviceKind) -> String {
        if let modelType = kind.modelType {
            switch modelType {
            case "NMOS":
                return "nmos"
            case "PMOS":
                return "pmos"
            default:
                break
            }
        }
        switch kind.spicePrefix {
        case "R":
            return "resistor"
        case "C":
            return "capacitor"
        case "M":
            return kind.modelType == "PMOS" ? "pmos" : "nmos"
        default:
            return kind.id
        }
    }

    static func deviceType(_ kind: DeviceKind) -> DeviceType {
        if let modelType = kind.modelType {
            switch modelType {
            case "PMOS":
                return .pmos
            case "NMOS":
                return .nmos
            default:
                break
            }
        }
        switch kind.spicePrefix {
        case "M":
            return kind.modelType == "PMOS" ? .pmos : .nmos
        default:
            return .passive
        }
    }
}
