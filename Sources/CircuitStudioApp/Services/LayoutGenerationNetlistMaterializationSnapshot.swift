import Foundation

enum LayoutGenerationNetlistMaterializationStatus: String, Sendable, Codable, Equatable {
    case none
    case succeeded
    case failed
}

struct LayoutGenerationNetlistMaterializationSnapshot: Sendable, Codable, Equatable {
    let status: LayoutGenerationNetlistMaterializationStatus
    let message: String?
}
