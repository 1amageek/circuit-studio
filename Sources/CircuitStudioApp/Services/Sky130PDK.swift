import Foundation

/// Locates the installed Sky130 PDK root shared by the signoff tools.
public enum Sky130PDK {

    /// Resolves the PDK root from `PDK_ROOT`, or from the single installed volare
    /// Sky130 build. Returns `nil` when the PDK is absent or the volare install
    /// is ambiguous (more than one build) — there is no silent fallback; the
    /// caller decides how to handle a missing PDK.
    public static func root(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        if let root = environment["PDK_ROOT"],
           fileManager.fileExists(atPath: root) {
            return root
        }
        let versions = NSString(string: "~/.volare/volare/sky130/versions")
            .expandingTildeInPath
        let entries: [String]
        do {
            entries = try fileManager.contentsOfDirectory(atPath: versions)
        } catch {
            return nil
        }
        let builds = entries.filter { !$0.hasPrefix(".") }
        guard builds.count == 1 else { return nil }
        return versions + "/" + builds[0]
    }
}
