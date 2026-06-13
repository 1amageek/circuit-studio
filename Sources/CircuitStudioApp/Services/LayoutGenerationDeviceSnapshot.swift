import Foundation

struct LayoutGenerationDeviceSnapshot: Sendable, Codable, Equatable {
    let name: String
    let deviceKindID: String
    let category: String
    let hasLayoutGenerator: Bool
    let cellName: String?
}
