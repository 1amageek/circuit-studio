import Foundation

/// Built-in MOSFET model presets for common use cases.
public enum BuiltInModelPresets {

    public static let all: [MOSFETModelPreset] = [
        genericNMOS,
        genericPMOS,
    ]

    public static let genericNMOS = MOSFETModelPreset(
        id: "generic_nmos",
        displayName: "Generic NMOS",
        description: "Educational generic NMOS (VTO=0.7V, KP=110uA/V\u{00B2})",
        modelType: "NMOS",
        parameters: [
            "vto": 0.7,
            "kp": 110e-6,
            "gamma": 0.4,
            "phi": 0.65,
            "lambda": 0.04,
        ]
    )

    public static let genericPMOS = MOSFETModelPreset(
        id: "generic_pmos",
        displayName: "Generic PMOS",
        description: "Educational generic PMOS (VTO=-0.7V, KP=50uA/V\u{00B2})",
        modelType: "PMOS",
        parameters: [
            "vto": -0.7,
            "kp": 50e-6,
            "gamma": 0.4,
            "phi": 0.65,
            "lambda": 0.04,
        ]
    )
}
