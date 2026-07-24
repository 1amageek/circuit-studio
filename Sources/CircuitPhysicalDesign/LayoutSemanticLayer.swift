import LayoutCore

enum LayoutSemanticLayer: Sendable, Hashable, CaseIterable {
    case nwell
    case active
    case poly
    case nimp
    case pimp
    case resi
    case contact
    case m1
    case m2
    case via1

    var canonicalID: LayoutLayerID {
        switch self {
        case .nwell: return LayoutLayerID(name: "NWELL", purpose: "drawing")
        case .active: return LayoutLayerID(name: "ACTIVE", purpose: "drawing")
        case .poly: return LayoutLayerID(name: "POLY", purpose: "drawing")
        case .nimp: return LayoutLayerID(name: "NIMP", purpose: "drawing")
        case .pimp: return LayoutLayerID(name: "PIMP", purpose: "drawing")
        case .resi: return LayoutLayerID(name: "RESI", purpose: "drawing")
        case .contact: return LayoutLayerID(name: "CONTACT", purpose: "cut")
        case .m1: return LayoutLayerID(name: "M1", purpose: "drawing")
        case .m2: return LayoutLayerID(name: "M2", purpose: "drawing")
        case .via1: return LayoutLayerID(name: "VIA1", purpose: "cut")
        }
    }

    var nameAliases: Set<String> {
        switch self {
        case .nwell: return ["NWELL", "N-WELL", "N_WELL"]
        case .active: return ["ACTIVE", "DIFF", "DIFFUSION", "OD", "AA", "RX"]
        case .poly: return ["POLY", "POLYSILICON", "PO", "GATE"]
        case .nimp: return ["NIMP", "NPLUS", "N+", "NSD", "N_IMPLANT"]
        case .pimp: return ["PIMP", "PPLUS", "P+", "PSD", "P_IMPLANT"]
        case .resi: return ["RESI", "RES", "RPO", "RESISTOR"]
        case .contact: return ["CONTACT", "CONT", "CA", "CO"]
        case .m1: return ["M1", "MET1", "METAL1", "LI1"]
        case .m2: return ["M2", "MET2", "METAL2"]
        case .via1: return ["VIA1", "V1", "VIA"]
        }
    }
}
