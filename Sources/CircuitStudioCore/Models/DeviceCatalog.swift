import Foundation

/// Registry of all available device types.
/// The single source of truth for device metadata used by the palette, inspector, and renderer.
public struct DeviceCatalog: Sendable {
    private var kinds: [String: DeviceKind] = [:]
    private var presetStore: [String: MOSFETModelPreset] = [:]

    public init() {}

    public mutating func register(_ kind: DeviceKind) {
        kinds[kind.id] = kind
    }

    public func device(for id: String) -> DeviceKind? {
        kinds[id]
    }

    public func allDevices() -> [DeviceKind] {
        Array(kinds.values).sorted { $0.displayName < $1.displayName }
    }

    public func devices(in category: DeviceCategory) -> [DeviceKind] {
        allDevices().filter { $0.category == category }
    }

    // MARK: - Model Presets

    public mutating func registerPreset(_ preset: MOSFETModelPreset) {
        presetStore[preset.id] = preset
    }

    public func preset(for id: String) -> MOSFETModelPreset? {
        presetStore[id]
    }

    public func presets(forModelType type: String) -> [MOSFETModelPreset] {
        presetStore.values
            .filter { $0.modelType == type }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Returns the default preset ID for a given device kind, if applicable.
    public func defaultPresetID(for deviceKindID: String) -> String? {
        guard let kind = device(for: deviceKindID),
              let modelType = kind.modelType else { return nil }
        switch modelType {
        case "NMOS": return "generic_nmos"
        case "PMOS": return "generic_pmos"
        default: return nil
        }
    }

    /// Returns the standard catalog containing all built-in devices and presets.
    public static func standard() -> DeviceCatalog {
        var catalog = DeviceCatalog()
        for kind in BuiltInDevices.all {
            catalog.register(kind)
        }
        for preset in BuiltInModelPresets.all {
            catalog.registerPreset(preset)
        }
        return catalog
    }
}
