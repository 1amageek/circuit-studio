import Foundation

enum TimingArtifactDateCoding {
    static func decode<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date {
        let value = try container.decode(String.self, forKey: key)
        if let date = formatter(options: [.withInternetDateTime]).date(from: value) {
            return date
        }
        if let date = formatter(options: [.withInternetDateTime, .withFractionalSeconds]).date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Expected an ISO-8601 UTC timestamp."
        )
    }

    static func encode<Key: CodingKey>(
        _ date: Date,
        to container: inout KeyedEncodingContainer<Key>,
        forKey key: Key
    ) throws {
        try container.encode(formatter(options: [.withInternetDateTime]).string(from: date), forKey: key)
    }

    private static func formatter(options: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
