import Testing
@testable import CircuitStudioApp

@Suite("NAND gate builder")
struct NANDGateBuilderTests {
    @Test("andN rejects empty input lists")
    func andNRejectsEmptyInputLists() throws {
        let builder = try NANDGateBuilder()

        #expect(throws: NANDGateBuilder.BuilderError.emptyAndInput) {
            try builder.andN([], "y")
        }
    }
}
