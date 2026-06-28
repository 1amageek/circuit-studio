import Foundation

struct TerminalKey: Sendable, Hashable {
    let componentID: UUID
    let componentName: String
    let pinName: String
}
