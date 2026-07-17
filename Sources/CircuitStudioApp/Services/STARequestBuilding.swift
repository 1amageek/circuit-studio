import STAEngine

public protocol STARequestBuilding: Sendable {
    func makeRequest(
        for netlist: SequentialNetlist,
        iteration: Int
    ) async throws -> STARequest
}
