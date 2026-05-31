import CryptoKit
import Foundation

public enum TimingTopologyHasher {
    public static func hash<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func hashModel(_ model: Level1DeviceModel) throws -> String {
        try hash(model)
    }
}
