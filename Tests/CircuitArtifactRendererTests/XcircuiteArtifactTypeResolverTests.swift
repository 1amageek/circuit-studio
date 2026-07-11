import ArtifactCore
import CircuitArtifactRenderer
import Testing
import XcircuitePackage

@Suite("Xcircuite artifact type resolver")
struct XcircuiteArtifactTypeResolverTests {
    private let resolver = XcircuiteArtifactTypeResolver()

    @Test func waveformFormatsUseCircuitOwnedTypes() {
        #expect(
            resolver.artifactType(kind: .waveform, format: .csv)
                == CircuitArtifactTypes.waveformCSV
        )
        #expect(
            resolver.artifactType(kind: .waveform, format: .raw)
                == CircuitArtifactTypes.waveformRAW
        )
    }

    @Test func genericFormatsKeepStandardMediaTypes() {
        #expect(resolver.artifactType(kind: .report, format: .json) == .json)
        #expect(resolver.artifactType(kind: .measurement, format: .csv) == .csv)
        #expect(resolver.artifactType(kind: .report, format: .text) == .plainText)
    }

    @Test func electronicDesignFormatsAreOwnedByTheConsumer() {
        #expect(resolver.artifactType(kind: .netlist, format: .spice) == CircuitArtifactTypes.spice)
        #expect(resolver.artifactType(kind: .technology, format: .lef) == CircuitArtifactTypes.lef)
        #expect(resolver.artifactType(kind: .layout, format: .def) == CircuitArtifactTypes.def)
        #expect(resolver.artifactType(kind: .parasitic, format: .spef) == CircuitArtifactTypes.spef)
        #expect(resolver.artifactType(kind: .layout, format: .oasis) == CircuitArtifactTypes.oasis)
        #expect(resolver.artifactType(kind: .layout, format: .gdsii) == CircuitArtifactTypes.gdsii)
    }

    @Test func unknownFormatDefersToFileDetection() {
        #expect(resolver.artifactType(kind: .other, format: .unknown) == nil)
    }
}
