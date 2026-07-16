import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("Persisted configuration versions")
struct PersistedConfigurationVersionTests {
    @Test func pexConfigurationRequiresCurrentVersion() throws {
        let current = Data(#"{"version":1,"topCell":"TOP"}"#.utf8)
        let decoded = try JSONDecoder().decode(PEXProjectConfig.self, from: current)
        #expect(decoded.version == PEXProjectConfig.currentVersion)

        let missing = Data(#"{"topCell":"TOP"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PEXProjectConfig.self, from: missing)
        }

        let unsupported = Data(#"{"version":2,"topCell":"TOP"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PEXProjectConfig.self, from: unsupported)
        }
    }

    @Test func technologyPackageManifestRequiresCurrentVersion() throws {
        let current = Data(#"{"version":1,"packageID":"pdk.test","name":"Test PDK"}"#.utf8)
        let decoded = try JSONDecoder().decode(TechnologyPackageManifest.self, from: current)
        #expect(decoded.version == TechnologyPackageManifest.currentVersion)

        let missing = Data(#"{"packageID":"pdk.test","name":"Test PDK"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TechnologyPackageManifest.self, from: missing)
        }

        let unsupported = Data(#"{"version":2,"packageID":"pdk.test","name":"Test PDK"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TechnologyPackageManifest.self, from: unsupported)
        }
    }
}
