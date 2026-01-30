import Foundation

/// Registry of all available device types.
/// The single source of truth for device metadata used by the palette, inspector, and renderer.
public struct DeviceCatalog: Sendable {
    private var kinds: [String: DeviceKind] = [:]

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

    /// Returns the standard catalog containing all built-in devices.
    public static func standard() -> DeviceCatalog {
        var catalog = DeviceCatalog()
        for kind in BuiltInDevices.all {
            catalog.register(kind)
        }
        return catalog
    }
}
