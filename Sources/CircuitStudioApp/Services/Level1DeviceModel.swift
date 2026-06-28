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

    public static func bundledDefault() -> Level1DeviceModel {
        bundledDefaultProfile().model
    }

    public static func bundledDefaultProfile() -> Level1DeviceModelProfile {
        do {
            return try bundledDefaultProfileSelection().profile
        } catch {
            preconditionFailure("Bundled default level-1 device model profile is missing or invalid: \(error)")
        }
    }

    public static func bundledDefaultTechnologyContext() -> TimingTechnologyContext {
        do {
            return try bundledDefaultProfileSelection().technologyContext
        } catch {
            preconditionFailure("Bundled default level-1 device model profile context is invalid: \(error)")
        }
    }

    public static func bundledDefaultProfileResourceName() -> String {
        do {
            let catalog = try TimingModelProfileCatalog.bundled()
            let entry = try catalog.entry(profileID: nil)
            guard let resourceName = entry.profileResourceName else {
                preconditionFailure("Bundled default level-1 device model profile is not a bundled resource.")
            }
            return resourceName
        } catch {
            preconditionFailure("Bundled default level-1 device model profile resource is missing: \(error)")
        }
    }

    public static func technologyContext(for model: Level1DeviceModel) -> TimingTechnologyContext {
        do {
            let defaultSelection = try bundledDefaultProfileSelection()
            if model == defaultSelection.profile.model {
                return defaultSelection.technologyContext
            }
        } catch {
            // A custom model can still produce an unprofiled context below.
        }

        do {
            return TimingTechnologyContext(
                processName: "custom-level1",
                cornerID: "unspecified",
                supplyVoltage: model.supplyVoltage,
                deviceModelID: "custom-level1-device-model",
                deviceModelHash: try TimingTopologyHasher.hashModel(model)
            )
        } catch {
            preconditionFailure("Custom level-1 device model context is invalid: \(error)")
        }
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
