import Foundation

public enum SimulationRunRecordingError: Error, LocalizedError, Equatable {
    case projectRequired

    public var errorDescription: String? {
        switch self {
        case .projectRequired:
            "Open or create a project before running a recorded simulation."
        }
    }
}
