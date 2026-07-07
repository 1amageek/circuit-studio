import Testing
@testable import CircuitStudioCore

@Suite("Transient progress channel")
struct TransientProgressChannelTests {
    @Test("Solution-width mismatch is recorded as a typed failure")
    func solutionWidthMismatchIsRecordedAsTypedFailure() throws {
        let channel = TransientProgressChannel()

        channel.append(time: 0, solution: [1, 2])
        channel.append(time: 1, solution: [3])

        let failure = try #require(channel.takeFailure())
        #expect(failure == .solutionWidthChanged(expected: 2, actual: 1))
    }
}
