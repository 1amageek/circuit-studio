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

    // MARK: - Project Cells

    /// Device-kind ID for a placed instance of the named project cell.
    public static func cellKindID(for cellName: String) -> String {
        "cell.\(cellName)"
    }

    /// A cell that could not be offered in the palette, with the reason.
    public struct CellCatalogIssue: Sendable {
        public let cellName: String
        public let reason: String

        public init(cellName: String, reason: String) {
            self.cellName = cellName
            self.reason = reason
        }
    }

    /// Result of folding a cell library into a catalog: the extended
    /// catalog plus the cells that had to be excluded and why. Issues are
    /// returned, not swallowed — the caller decides how to surface them.
    public struct CellCatalogBuildResult: Sendable {
        public let catalog: DeviceCatalog
        public let issues: [CellCatalogIssue]

        public init(catalog: DeviceCatalog, issues: [CellCatalogIssue]) {
            self.catalog = catalog
            self.issues = issues
        }
    }

    /// Returns a copy of this catalog extended with a device kind per
    /// placeable library cell.
    ///
    /// `activeCellName` and every cell that transitively instantiates it
    /// are excluded — placing them would create a hierarchy cycle. Cells
    /// whose interface fails to derive are excluded and reported as issues.
    public func includingCells(
        from library: CellLibrary,
        activeCellName: String?
    ) -> CellCatalogBuildResult {
        var catalog = self
        var issues: [CellCatalogIssue] = []

        for cell in library.cells {
            if let active = activeCellName, library.reaches(from: cell.name, to: active) {
                continue
            }
            let interface: CellInterface
            do {
                interface = try CellInterface.derive(from: cell.schematic)
            } catch {
                issues.append(CellCatalogIssue(
                    cellName: cell.name,
                    reason: error.localizedDescription
                ))
                continue
            }
            let (symbol, portDefinitions) = CellSymbolFactory.make(
                cellName: cell.name,
                interface: interface
            )
            catalog.register(DeviceKind(
                id: Self.cellKindID(for: cell.name),
                displayName: cell.name,
                category: .cell,
                spicePrefix: "X",
                portDefinitions: portDefinitions,
                parameterSchema: [],
                symbol: symbol,
                cellName: cell.name
            ))
        }

        return CellCatalogBuildResult(catalog: catalog, issues: issues)
    }
}
