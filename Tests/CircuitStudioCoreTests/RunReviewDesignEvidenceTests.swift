import Foundation
import Testing
import CircuiteFoundation
import DesignFlowKernel
import Xcircuite
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
        #expect(schematic.artifact.reference.locator.location.value == fixture.designSpecPath)
        #expect(!schematic.document.components.isEmpty)
        #expect(!schematic.document.wires.isEmpty)

        let layout = try #require(evidence.layout)
        #expect(layout.artifact.reference.locator.location.value == fixture.layoutDocumentPath)
        #expect(!layout.document.cells.isEmpty)
        #expect(layout.document.cells.contains { !$0.shapes.isEmpty })

        #expect(evidence.waveforms.map(\.phase) == [.preLayout, .postLayout])
        #expect(evidence.waveforms.allSatisfy { !$0.preview.signals.isEmpty })
        #expect(evidence.netlists.isEmpty)
        #expect(evidence.issues.isEmpty)
    }

    @MainActor
    @Test func waveformProjectionSamplesTheWholeArtifact() async throws {
        let runID = "run-signoff"
        let path = ".xcircuite/runs/\(runID)/analysis-waveform.csv"
        let rows = (0..<5_000).map { index in
            "\(index),\(index.isMultiple(of: 2) ? 0 : 1)"
        }
        let data = Data((["time,V(out)"] + rows).joined(separator: "\n").utf8)
        let reference = try RunReviewTestSupport.artifactReference(
            artifactID: "analysis-waveform",
            path: path,
            payload: data,
            kind: .waveform,
            format: .csv
        )
        let fixture = try await RunReviewSignoffFixture.make(
            additionalArtifacts: [reference],
            additionalArtifactPayloads: [path: data]
        )
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        let review = try await fixture.service.loadRun(
            runID: fixture.runID,
            projectRoot: fixture.root
        )
        let evidence = await fixture.service.loadDesignEvidence(
            runID: fixture.runID,
            bundle: review.bundle,
            projectRoot: fixture.root
        )
        let waveform = try #require(evidence.waveforms.first {
            $0.artifact.reference.id.rawValue == "analysis-waveform"
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
