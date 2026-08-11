import Database
import DatabaseKitFoundation
import Foundation

struct ActivityDatabaseWallClock: WallClock {
    var now: Timestamp {
        do {
            return try Timestamp(Date())
        } catch {
            preconditionFailure("The platform clock produced an invalid timestamp: \(error)")
        }
    }
}
