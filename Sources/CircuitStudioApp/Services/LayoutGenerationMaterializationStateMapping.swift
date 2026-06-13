import Foundation

extension LayoutGenerationNetlistMaterializationSnapshot {
    init(_ state: NetlistSchematicMaterializationState) {
        switch state {
        case .none:
            self.init(status: .none, message: nil)
        case .succeeded(let message):
            self.init(status: .succeeded, message: message)
        case .failed(let message):
            self.init(status: .failed, message: message)
        }
    }
}
