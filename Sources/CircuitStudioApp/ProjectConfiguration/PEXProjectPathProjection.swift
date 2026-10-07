import Foundation
import PEXEngine

/// Projects path-valued config fields between explicit document/project contexts.
struct PEXProjectPathProjection {
    static func project(_ config: PEXProjectConfig, from sourceDirectory: URL,
                        to destinationDirectory: URL) -> PEXProjectConfig {
        func path(_ value: String) -> String {
            guard !value.hasPrefix("/"), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return value
            }
            let target = sourceDirectory.appending(path: value).standardizedFileURL.pathComponents
            let base = destinationDirectory.standardizedFileURL.pathComponents
            var common = 0
            while common < min(target.count, base.count), target[common] == base[common] { common += 1 }
            let components = Array(repeating: "..", count: base.count - common) + Array(target.dropFirst(common))
            return components.isEmpty ? "." : components.joined(separator: "/")
        }
        var result = config
        result.inputs.layout = path(config.inputs.layout)
        result.inputs.netlist = path(config.inputs.netlist)
        result.inputs.technology = path(config.inputs.technology)
        result.inputs.technologyByCorner = config.inputs.technologyByCorner.mapValues(path)
        result.inputs.nativeInput = config.inputs.nativeInput.map(path)
        result.output.workspace = path(config.output.workspace)
        result.executablePath = config.executablePath.map(path)
        result.processProfile = config.processProfile.map { profile in
            .init(profileID: profile.profileID, pdkID: profile.pdkID, source: profile.source,
                requirementID: profile.requirementID, pdkRoot: profile.pdkRoot.map(path),
                primaryDeckPath: profile.primaryDeckPath.map(path),
                cornerDeckPaths: profile.cornerDeckPaths.mapValues(path),
                requiredViewPaths: profile.requiredViewPaths.mapValues(path), metadata: profile.metadata)
        }
        return result
    }
}
