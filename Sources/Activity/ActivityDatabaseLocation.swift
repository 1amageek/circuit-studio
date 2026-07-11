import Foundation

public enum ActivityDatabaseLocation {
    public static let applicationIdentifier = "team.stamp.Xcircuite"

    public static func applicationDatabaseURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = supportURL
            .appendingPathComponent(applicationIdentifier, isDirectory: true)
            .appendingPathComponent("Activity", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ActivityStoreError.databasePathCreationFailed(error.localizedDescription)
        }
        return directory.appendingPathComponent("activity.sqlite", isDirectory: false)
    }
}
