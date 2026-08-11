import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignFlowKernel
import Foundation
import ReleaseCore
import ToolQualification

struct ReleaseReviewXORFixture {
    let result: LayoutXORResult
    let retainedArtifacts: [ArtifactReference]
    let retainedBindings: [FlowArtifactBinding]
    let artifactPayloads: [String: Data]
    let pdkDigest: String

    static func make(
        prefix: String,
        layoutDigest: String,
        evaluatedAt: Date
    ) async throws -> Self {
        let toolBytes = Data("qualified-layout-xor".utf8)
        let oracleBytes = Data("independent-layout-xor".utf8)
        let digester = SHA256ContentDigester()
        let toolDigest = try digester.digest(data: toolBytes)
        let oracleDigest = try digester.digest(data: oracleBytes)
        let toolProducer = try ProducerIdentity(
            kind: .tool,
            identifier: "qualified-layout-xor",
            version: "1.0.0",
            build: toolDigest.hexadecimalValue
        )
        let oracleProducer = try ProducerIdentity(
            kind: .tool,
            identifier: "independent-layout-xor",
            version: "1.0.0",
            build: oracleDigest.hexadecimalValue
        )
        let sourceProducer = try ProducerIdentity(
            kind: .library,
            identifier: "release-review-fixture",
            version: "1.0.0"
        )
        let issuer = try ProducerIdentity(
            kind: .engine,
            identifier: "release-review-qualification",
            version: "1.0.0"
        )

        var payloads: [ArtifactID: Data] = [:]
        var payloadsByLogicalID: [String: Data] = [:]
        var bindingsByLogicalID: [String: FlowArtifactBinding] = [:]
        func artifact(
            id: String,
            name: String,
            payload: Data,
            kind: ArtifactKind,
            producer: ProducerIdentity
        ) throws -> ArtifactReference {
            let reference = try RunReviewTestSupport.artifactReference(
                artifactID: id,
                path: "\(prefix)/qualification/\(name)",
                payload: payload,
                kind: kind,
                producer: producer
            )
            payloads[reference.id] = payload
            payloadsByLogicalID[id] = payload
            bindingsByLogicalID[id] = try RunReviewTestSupport.artifactBinding(
                reference: reference,
                artifactID: id,
                path: "\(prefix)/qualification/\(name)",
                producer: producer
            )
            return reference
        }

        let tool = try artifact(
            id: "xor-tool",
            name: "tool.bin",
            payload: toolBytes,
            kind: .other,
            producer: toolProducer
        )
        let oracleTool = try artifact(
            id: "xor-oracle-tool",
            name: "oracle.bin",
            payload: oracleBytes,
            kind: .other,
            producer: oracleProducer
        )
        let process = try artifact(
            id: "xor-process",
            name: "process.json",
            payload: Data("process".utf8),
            kind: .technology,
            producer: sourceProducer
        )
        let pdk = try artifact(
            id: "xor-pdk",
            name: "pdk.json",
            payload: Data("pdk".utf8),
            kind: .technology,
            producer: sourceProducer
        )
        let deck = try artifact(
            id: "xor-deck",
            name: "deck.json",
            payload: Data("deck".utf8),
            kind: .ruleDeck,
            producer: sourceProducer
        )
        let input = try artifact(
            id: "xor-input",
            name: "input.gds",
            payload: Data("layout".utf8),
            kind: .layout,
            producer: sourceProducer
        )
        let streamed = try artifact(
            id: "xor-streamed",
            name: "streamed.gds",
            payload: Data("layout".utf8),
            kind: .layout,
            producer: sourceProducer
        )
        let report = try artifact(
            id: "xor-report",
            name: "report.json",
            payload: Data("{\"differenceCount\":0}".utf8),
            kind: .report,
            producer: toolProducer
        )
        let oracleOutput = try artifact(
            id: "xor-oracle-output",
            name: "oracle-report.json",
            payload: Data(
                "{\"differenceCount\":0,\"producer\":\"independent-layout-xor\"}".utf8
            ),
            kind: .report,
            producer: oracleProducer
        )
        let scope = ToolQualificationScope(
            implementationID: toolProducer.identifier,
            toolVersion: toolProducer.version,
            binaryDigest: tool.digest.hexadecimalValue,
            algorithmVersion: "geometric-xor-v1",
            processProfileID: "release-review-process",
            processProfileDigest: process.digest.hexadecimalValue,
            deckDigest: deck.digest.hexadecimalValue,
            pdkID: "release-review-pdk",
            pdkDigest: pdk.digest.hexadecimalValue,
            oracle: ToolOracleQualificationScope(
                implementationID: oracleProducer.identifier,
                version: oracleProducer.version,
                binaryDigest: oracleTool.digest.hexadecimalValue
            )
        )
        let outcome = ToolQualificationCaseOutcome(
            caseID: "xor-zero-difference",
            coverageTags: ["release"],
            comparisons: [ToolQualificationMetricComparison(
                metricID: "difference-count",
                observed: 0,
                expected: 0
            )]
        )
        let corpus = ToolCorpusQualificationResult(
            resultID: "xor-corpus",
            qualificationID: "release-review-xor",
            toolID: toolProducer.identifier,
            scope: scope,
            issuer: issuer,
            inputArtifacts: [input],
            outputArtifacts: [report],
            cases: [outcome],
            checkedAt: evaluatedAt
        )
        let oracle = ToolOracleQualificationResult(
            resultID: "xor-oracle",
            qualificationID: "release-review-xor",
            primaryToolID: toolProducer.identifier,
            oracleToolID: oracleProducer.identifier,
            scope: scope,
            issuer: issuer,
            inputArtifacts: [input],
            primaryOutputArtifacts: [report],
            oracleOutputArtifacts: [oracleOutput],
            cases: [ToolOracleCaseComparison(
                caseID: outcome.caseID,
                primary: outcome,
                oracle: outcome,
                agreementComparisons: [ToolOracleMetricComparison(
                    metricID: "difference-count",
                    primaryObserved: 0,
                    oracleObserved: 0
                )]
            )],
            checkedAt: evaluatedAt
        )
        let health = ToolHealthQualificationResult(
            resultID: "xor-health",
            qualificationID: "release-review-xor",
            toolID: toolProducer.identifier,
            scope: scope,
            issuer: issuer,
            inputArtifacts: [input],
            outputArtifacts: [report],
            checkedAt: evaluatedAt
        )
        let corpusArtifact = try artifact(
            id: "xor-corpus-evidence",
            name: "corpus.json",
            payload: try corpus.canonicalData(),
            kind: .evidence,
            producer: issuer
        )
        let oracleArtifact = try artifact(
            id: "xor-oracle-evidence",
            name: "oracle.json",
            payload: try oracle.canonicalData(),
            kind: .evidence,
            producer: issuer
        )
        let healthArtifact = try artifact(
            id: "xor-health-evidence",
            name: "health.json",
            payload: try health.canonicalData(),
            kind: .evidence,
            producer: issuer
        )
        let qualification = try await ToolProcessQualificationEvidenceBuilder().build(
            ToolProcessQualificationEvidenceBuildRequest(
                qualificationID: "release-review-xor",
                toolID: toolProducer.identifier,
                scope: scope,
                identityArtifacts: ToolProcessQualificationArtifacts(
                    toolExecutable: tool,
                    processProfile: process,
                    pdk: pdk,
                    ruleDeck: deck,
                    oracleExecutable: oracleTool
                ),
                corpusResultArtifacts: [corpusArtifact],
                oracleResultArtifacts: [oracleArtifact],
                healthResultArtifacts: [healthArtifact],
                inputArtifacts: [input],
                outputArtifacts: [report, oracleOutput],
                qualifiedAt: evaluatedAt.addingTimeInterval(-1),
                expiresAt: evaluatedAt.addingTimeInterval(60)
            ),
            reading: ReleaseReviewQualificationArtifactReader(payloads: payloads),
            at: evaluatedAt
        )
        let provenance = try ExecutionProvenance(
            producer: toolProducer,
            inputs: [input, streamed],
            invocation: try .externalProcess(executable: "/tools/layout-xor"),
            environment: try ExecutionEnvironmentFingerprint(
                platform: "macos",
                architecture: "arm64",
                toolchain: "release-review-xor"
            ),
            startedAt: evaluatedAt,
            completedAt: evaluatedAt
        )
        guard let reportFlowBinding = bindingsByLogicalID["xor-report"] else {
            throw ReleaseReviewQualificationArtifactReaderError.missingBinding("xor-report")
        }
        let reportBinding = try ReleaseArtifactBinding(
            logicalID: reportFlowBinding.logicalID,
            reference: reportFlowBinding.reference,
            availability: reportFlowBinding.availability
        )
        let qualificationBindings = try bindingsByLogicalID.values.map {
            try ReleaseArtifactBinding(
                logicalID: $0.logicalID,
                reference: $0.reference,
                availability: $0.availability
            )
        }
        let result = LayoutXORResult(
            status: .passed,
            method: .geometricXOR,
            sourceDigest: input.digest.hexadecimalValue,
            streamedDigest: streamed.digest.hexadecimalValue,
            message: "Qualified geometric XOR found no differences.",
            evidenceBinding: reportBinding,
            processQualification: qualification,
            qualificationBindings: qualificationBindings,
            executionStatus: .completed,
            exitCode: 0,
            differenceCount: 0,
            differenceAreaSquareMicrometers: 0,
            rawReportDigest: report.digest,
            provenance: provenance
        )
        let retained = Array(Set(
            qualification.identityArtifacts.all
                + qualification.evidenceArtifacts
                + qualification.inputArtifacts
                + qualification.outputArtifacts
                + [report, input, streamed]
        ))
        let retainedBindings = bindingsByLogicalID.values.sorted {
            $0.logicalID < $1.logicalID
        }
        let retainedPayloads = try Dictionary(uniqueKeysWithValues: retainedBindings.map { binding in
            guard let payload = payloadsByLogicalID[binding.logicalID] else {
                throw ReleaseReviewQualificationArtifactReaderError.missingPayload(binding.reference.id)
            }
            return (try binding.requireLocalRelativePath().stringValue, payload)
        })
        return Self(
            result: result,
            retainedArtifacts: retained,
            retainedBindings: retainedBindings,
            artifactPayloads: retainedPayloads,
            pdkDigest: pdk.digest.hexadecimalValue
        )
    }
}

private enum ReleaseReviewQualificationArtifactReaderError: Error {
    case missingPayload(ArtifactID)
    case digestMismatch(ArtifactID)
    case missingBinding(String)
}

private struct ReleaseReviewQualificationArtifactReader: ToolQualificationArtifactReading {
    let payloads: [ArtifactID: Data]

    func verifiedData(for reference: ArtifactReference) async throws -> Data {
        guard let payload = payloads[reference.id] else {
            throw ReleaseReviewQualificationArtifactReaderError.missingPayload(reference.id)
        }
        guard try SHA256ContentDigester().digest(data: payload) == reference.digest,
              UInt64(payload.count) == reference.byteCount else {
            throw ReleaseReviewQualificationArtifactReaderError.digestMismatch(reference.id)
        }
        return payload
    }
}
