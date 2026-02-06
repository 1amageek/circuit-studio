import Foundation

/// Runtime configuration for applying a process technology and corner selection.
public struct ProcessConfiguration: Sendable, Codable, Hashable {
    public var technology: ProcessTechnology?
    public var cornerID: UUID?
    public var includePaths: [String]
    public var parameterOverrides: [String: Double]
    public var temperatureOverride: Double?
    public var resolveIncludes: Bool

    public init(
        technology: ProcessTechnology? = nil,
        cornerID: UUID? = nil,
        includePaths: [String] = [],
        parameterOverrides: [String: Double] = [:],
        temperatureOverride: Double? = nil,
        resolveIncludes: Bool = false
    ) {
        self.technology = technology
        self.cornerID = cornerID
        self.includePaths = includePaths
        self.parameterOverrides = parameterOverrides
        self.temperatureOverride = temperatureOverride
        self.resolveIncludes = resolveIncludes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.technology = try container.decodeIfPresent(ProcessTechnology.self, forKey: .technology)
        self.cornerID = try container.decodeIfPresent(UUID.self, forKey: .cornerID)
        self.includePaths = try container.decodeIfPresent([String].self, forKey: .includePaths) ?? []
        self.parameterOverrides = try container.decodeIfPresent([String: Double].self, forKey: .parameterOverrides) ?? [:]
        self.temperatureOverride = try container.decodeIfPresent(Double.self, forKey: .temperatureOverride)
        self.resolveIncludes = try container.decodeIfPresent(Bool.self, forKey: .resolveIncludes) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(technology, forKey: .technology)
        try container.encodeIfPresent(cornerID, forKey: .cornerID)
        try container.encode(includePaths, forKey: .includePaths)
        try container.encode(parameterOverrides, forKey: .parameterOverrides)
        try container.encodeIfPresent(temperatureOverride, forKey: .temperatureOverride)
        try container.encode(resolveIncludes, forKey: .resolveIncludes)
    }

    public var isEmpty: Bool {
        technology == nil
        && cornerID == nil
        && includePaths.isEmpty
        && parameterOverrides.isEmpty
        && temperatureOverride == nil
        && resolveIncludes == false
    }

    public func effectiveCorner() -> Corner? {
        guard let technology else { return nil }
        if let cornerID {
            return technology.corner(id: cornerID)
        }
        if let defaultID = technology.defaultCornerID {
            return technology.corner(id: defaultID)
        }
        return technology.cornerSet.corners.first
    }

    public func effectiveTemperature(defaultValue: Double = 27.0) -> Double {
        if let temperatureOverride {
            return temperatureOverride
        }
        if let cornerTemp = effectiveCorner()?.temperature {
            return cornerTemp
        }
        if let technology {
            return technology.defaultTemperature
        }
        return defaultValue
    }

    public func effectiveParameters() -> [String: Double] {
        var merged = technology?.globalParameters ?? [:]
        if let corner = effectiveCorner() {
            for (name, value) in corner.parameterOverrides {
                merged[name] = value
            }
        }
        for (name, value) in parameterOverrides {
            merged[name] = value
        }
        return merged
    }

    public func effectiveIncludePaths() -> [String] {
        var result: [String] = []
        if let technology {
            appendUnique(technology.includePaths, to: &result)
        }
        appendUnique(includePaths, to: &result)
        return result
    }

    public func librarySection(for library: ProcessLibrary) -> String? {
        if let corner = effectiveCorner(),
           let override = corner.librarySectionOverrides[library.id] {
            return override
        }
        return library.defaultSection
    }

    private func appendUnique(_ paths: [String], to result: inout [String]) {
        for path in paths where !result.contains(path) {
            result.append(path)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case technology
        case cornerID
        case includePaths
        case parameterOverrides
        case temperatureOverride
        case resolveIncludes
    }
}
