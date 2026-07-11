import Foundation

public struct ActivityStoreMetrics: Sendable, Hashable {
    public let rowCount: Int
    public let databaseByteCount: Int64?

    public init(rowCount: Int, databaseByteCount: Int64?) {
        self.rowCount = rowCount
        self.databaseByteCount = databaseByteCount
    }
}
