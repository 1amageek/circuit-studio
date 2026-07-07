import Foundation

/// A level-1 (Shichman–Hodges) MOSFET model pair the timing characterizer drives in
/// CoreSpice — the same model envelope the CoreSpice⇔ngspice trust gate validates, so the
/// timing numbers rest on physics CoreSpice is known to compute correctly. Level-1 basic
/// I–V carries no intrinsic gate capacitance, so the characterizer models load EXPLICITLY:
/// `inputCapacitance` is derived here from oxide capacitance × gate area and applied as a
/// lumped cap both when characterizing (the swept output load) and when validating against
/// SPICE (a load on each path net), keeping the abstraction self-consistent.
public struct Level1DeviceModel: Sendable, Hashable, Codable {
    public let supplyVoltage: Double      // VDD (volts)
    public let nmosModelName: String
    public let pmosModelName: String
    public let nmosCard: String           // ".model <name> NMOS level=1 ..."
    public let pmosCard: String
    public let oxideCapPerArea: Double     // Cox (F/m^2), for the lumped input-cap model

    public init(supplyVoltage: Double, nmosModelName: String, pmosModelName: String,
                nmosCard: String, pmosCard: String, oxideCapPerArea: Double) {
        self.supplyVoltage = supplyVoltage
        self.nmosModelName = nmosModelName
        self.pmosModelName = pmosModelName
        self.nmosCard = nmosCard
        self.pmosCard = pmosCard
        self.oxideCapPerArea = oxideCapPerArea
    }

    public static func loadBundledDefault() throws -> Level1DeviceModel {
        try loadBundledDefaultProfile().model
    }

    public static func loadBundledDefaultProfile() throws -> Level1DeviceModelProfile {
        try bundledDefaultProfileSelection().profile
    }

    public static func loadBundledDefaultTechnologyContext() throws -> TimingTechnologyContext {
        try bundledDefaultProfileSelection().technologyContext
    }

    public static func loadBundledDefaultProfileResourceName() throws -> String {
        let catalog = try TimingModelProfileCatalog.bundled()
        let entry = try catalog.entry(profileID: nil)
        guard let resourceName = entry.profileResourceName else {
            throw TimingModelProfileCatalogError.missingProfileReference(entry.profileID)
        }
        return resourceName
    }

    public static func technologyContextChecked(for model: Level1DeviceModel) throws -> TimingTechnologyContext {
        do {
            let defaultSelection = try bundledDefaultProfileSelection()
            if model == defaultSelection.profile.model {
                return defaultSelection.technologyContext
            }
        } catch {
            // Custom model contexts do not require the bundled default profile.
        }
        return TimingTechnologyContext(
            processName: "custom-level1",
            cornerID: "unspecified",
            supplyVoltage: model.supplyVoltage,
            deviceModelID: "custom-level1-device-model",
            deviceModelHash: try TimingTopologyHasher.hashModel(model)
        )
    }

    public static func bundledDefault() throws -> Level1DeviceModel {
        try loadBundledDefault()
    }

    public static func bundledDefaultProfile() throws -> Level1DeviceModelProfile {
        try loadBundledDefaultProfile()
    }

    public static func bundledDefaultTechnologyContext() throws -> TimingTechnologyContext {
        try loadBundledDefaultTechnologyContext()
    }

    public static func bundledDefaultProfileResourceName() throws -> String {
        try loadBundledDefaultProfileResourceName()
    }

    public static func technologyContext(for model: Level1DeviceModel) throws -> TimingTechnologyContext {
        try technologyContextChecked(for: model)
    }

    private struct DefaultProfileSelection {
        let profile: Level1DeviceModelProfile
        let technologyContext: TimingTechnologyContext
    }

    private static func bundledDefaultProfileSelection() throws -> DefaultProfileSelection {
        let catalog = try TimingModelProfileCatalog.bundled()
        let entry = try catalog.entry(profileID: nil)
        if let resourceName = entry.profileResourceName {
            let profile = try Level1DeviceModelProfile.bundled(resourceName: resourceName)
            guard profile.profileID == entry.profileID else {
                throw TimingModelProfileCatalogError.profileNotFound(entry.profileID)
            }
            return try DefaultProfileSelection(
                profile: profile,
                technologyContext: profile.technologyContext(resourceName: resourceName)
            )
        }

        if let profilePath = entry.profilePath {
            let url = URL(filePath: profilePath)
            let profile = try Level1DeviceModelProfile.load(from: url)
            guard profile.profileID == entry.profileID else {
                throw TimingModelProfileCatalogError.profileNotFound(entry.profileID)
            }
            return try DefaultProfileSelection(
                profile: profile,
                technologyContext: profile.technologyContext(path: url.path(percentEncoded: false))
            )
        }

        throw TimingModelProfileCatalogError.missingProfileReference(entry.profileID)
    }

    /// Both `.model` cards, one per line.
    public var modelCards: String { "\(nmosCard)\n\(pmosCard)" }

    /// The lumped input capacitance a cell pin presents: Cox × Σ(W·L) over the devices that
    /// pin gates (W, L are in microns in `Device`, converted to metres here).
    public func inputCapacitance(of cell: CMOSGateNetlist, pin: String) -> Double {
        let micron = 1e-6
        var area = 0.0
        for device in cell.devices where device.gate == pin {
            let w = device.width * micron
            let l = device.length * micron
            area += w * l
        }
        return oxideCapPerArea * area
    }
}
