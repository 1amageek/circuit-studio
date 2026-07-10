import Foundation
import Testing
import XcircuitePackage
@testable import CircuitStudioApp

@Suite("Run review design evidence", .timeLimit(.minutes(2)))
struct RunReviewDesignEvidenceTests {
    @MainActor
    @Test func loadsCanonicalCircuitLayoutAndWaveforms() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        let evidence = await fixture.service.loadDesignEvidence(
            runID: fixture.runID,
            bundle: fixture.review.bundle,
            projectRoot: fixture.root
        )

        let schematic = try #require(evidence.schematic)
        #expect(schematic.sourceKind == .designSpec)
        #expect(schematic.artifact.path == fixture.designSpecPath)
        #expect(!schematic.document.components.isEmpty)
        #expect(!schematic.document.wires.isEmpty)

        let layout = try #require(evidence.layout)
        #expect(layout.artifact.path == fixture.layoutDocumentPath)
        #expect(!layout.document.cells.isEmpty)
        #expect(layout.document.cells.contains { !$0.shapes.isEmpty })

        #expect(evidence.waveforms.map(\.phase) == [.preLayout, .postLayout])
        #expect(evidence.waveforms.allSatisfy { !$0.preview.signals.isEmpty })
        #expect(evidence.netlists.isEmpty)
        #expect(evidence.issues.isEmpty)
    }

    @MainActor
    @Test func waveformProjectionSamplesTheWholeArtifact() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        let path = ".xcircuite/runs/\(fixture.runID)/analysis-waveform.csv"
        let rows = (0..<5_000).map { index in
            "\(index),\(index.isMultiple(of: 2) ? 0 : 1)"
        }
        let data = Data((["time,V(out)"] + rows).joined(separator: "\n").utf8)
        let url = fixture.root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        let reference = XcircuiteFileReference(
            artifactID: "analysis-waveform",
            path: path,
            kind: .waveform,
            format: .csv,
            sha256: XcircuiteHasher().sha256(data: data),
            byteCount: Int64(data.count),
            producedByRunID: fixture.runID
        )
        try XcircuitePackageStore().upsertRunArtifacts(
            [reference],
            runID: fixture.runID,
            inProjectAt: fixture.root
        )

        let review = try fixture.service.loadRun(runID: fixture.runID, projectRoot: fixture.root)
        let evidence = await fixture.service.loadDesignEvidence(
            runID: fixture.runID,
            bundle: review.bundle,
            projectRoot: fixture.root
        )
        let waveform = try #require(evidence.waveforms.first {
            $0.artifact.artifactID == "analysis-waveform"
        })
        let signal = try #require(waveform.preview.signals.first)

        #expect(signal.samples.count <= 1_026)
        #expect(signal.samples.first?.sweepValue == 0)
        #expect(signal.samples.last?.sweepValue == 4_999)
        #expect(signal.samples.contains { $0.signalValue == 0 })
        #expect(signal.samples.contains { $0.signalValue == 1 })
    }

    @MainActor
    @Test func refusesTamperedLayoutArtifact() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        let layoutURL = fixture.root.appending(path: fixture.layoutDocumentPath)
        var tamperedData = try Data(contentsOf: layoutURL)
        #expect(!tamperedData.isEmpty)
        tamperedData[tamperedData.startIndex] ^= 0x01
        try tamperedData.write(to: layoutURL, options: .atomic)
        let evidence = await fixture.service.loadDesignEvidence(
            runID: fixture.runID,
            bundle: fixture.review.bundle,
            projectRoot: fixture.root
        )

        #expect(evidence.layout == nil)
        #expect(evidence.issues.contains {
            $0.artifactPath == fixture.layoutDocumentPath
                && $0.message.contains("SHA-256")
        })
    }
}
