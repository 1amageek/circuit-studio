import Foundation

/// The verifiable provenance of a closed design: every signoff claim the flow makes -
/// functional, timing, DRC, LVS and other physical axes - paired with the measurement and a
/// link to the real tool artifact that backs it. Supporting evidence can be recorded in the
/// same bundle, but only signoff claims satisfy required verification axes.
public struct TapeoutEvidenceBundle: Sendable, Codable, Hashable {
    public static let currentSchemaVersion = 3
    public static let defaultRequiredAxes: [Axis] = [.functional, .timing, .drc, .lvs]

    public enum Axis: String, Sendable, Codable, Hashable {
        case functional   // golden-trace execution match
        case timing       // STA setup/hold closure (and STA⇔SPICE agreement)
        case drc          // Magic design-rule check
        case lvs          // Netgen layout-vs-schematic
        case erc          // electrical-rule check (floating/multiply-driven/undriven nets)
        case antenna      // Magic antennacheck (gate-oxide plasma-charge protection)
        case density      // Magic metal-density window (CMP)
        case ir           // power-grid IR drop (CoreSpice DC, ngspice-validated)
        case em           // electromigration current-density limit
    }

    public struct Claim: Sendable, Codable, Hashable {
        public static let antennaProtectionPlanStatement = "antenna protection plan is materialized in the generated layout"

        public enum Kind: String, Sendable, Codable, Hashable {
            case signoff
            case supportingEvidence
        }

        public let axis: Axis
        public let statement: String    // the asserted property
        public let passed: Bool
        public let measured: String     // the measured value / result
        public let artifact: TapeoutEvidenceArtifact?
        public let kind: Kind

        public init(
            axis: Axis,
            statement: String,
            passed: Bool,
            measured: String,
            artifact: TapeoutEvidenceArtifact?,
            kind: Kind
        ) {
            self.axis = axis; self.statement = statement; self.passed = passed
            self.measured = measured; self.artifact = artifact; self.kind = kind
        }

        private enum CodingKeys: String, CodingKey {
            case axis
            case statement
            case passed
            case measured
            case artifact
            case kind
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            axis = try container.decode(Axis.self, forKey: .axis)
            statement = try container.decode(String.self, forKey: .statement)
            passed = try container.decode(Bool.self, forKey: .passed)
            measured = try container.decode(String.self, forKey: .measured)
            artifact = try container.decodeIfPresent(TapeoutEvidenceArtifact.self, forKey: .artifact)
            guard let decodedKind = try container.decodeIfPresent(Kind.self, forKey: .kind) else {
                throw DecodingError.keyNotFound(
                    CodingKeys.kind,
                    DecodingError.Context(
                        codingPath: container.codingPath + [CodingKeys.kind],
                        debugDescription: "Claim.kind is required for standalone claim decoding."
                    )
                )
            }
            kind = decodedKind
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(axis, forKey: .axis)
            try container.encode(statement, forKey: .statement)
            try container.encode(passed, forKey: .passed)
            try container.encode(measured, forKey: .measured)
            try container.encodeIfPresent(artifact, forKey: .artifact)
            try container.encode(kind, forKey: .kind)
        }
    }

    public enum VerificationError: Error, LocalizedError, Equatable {
        case noClaims
        case missingAxis(Axis)
        case claimFailed(axis: Axis, statement: String)
        case missingArtifactReference(axis: Axis, statement: String)
        case artifactRunDirectoryRequired(axis: Axis, path: String)
        case artifactIntegrityFailed(axis: Axis, path: String, reason: String)

        public var errorDescription: String? {
            switch self {
            case .noClaims: return "The evidence bundle has no claims."
            case .missingAxis(let a): return "The bundle is missing the required \(a.rawValue) axis."
            case .claimFailed(let a, let s): return "Claim failed (\(a.rawValue)): \(s)."
            case .missingArtifactReference(let a, let s):
                return "Claim is missing a backing artifact (\(a.rawValue)): \(s)."
            case .artifactRunDirectoryRequired(let a, let p):
                return "Backing artifact for \(a.rawValue) requires a run directory for integrity verification: \(p)."
            case .artifactIntegrityFailed(let a, let p, let reason):
                return "Backing artifact for \(a.rawValue) failed integrity verification at \(p): \(reason)."
            }
        }
    }

    public let schemaVersion: Int
    public let designName: String
    public let targetClockPeriod: Double?
    public let claims: [Claim]
    public let gdsPath: String?

    public init(
        designName: String,
        targetClockPeriod: Double?,
        claims: [Claim],
        gdsPath: String?
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.designName = designName
        self.targetClockPeriod = targetClockPeriod
        self.claims = claims
        self.gdsPath = gdsPath
    }

    public func closesPresentSignoffAxes() -> Bool {
        let axes = Set(claims.filter { $0.kind == .signoff }.map(\.axis))
        guard !axes.isEmpty else { return false }
        do {
            try verify(requiredAxes: Array(axes), requireArtifacts: false)
            return true
        } catch {
            return false
        }
    }
    public var failing: [Claim] { claims.filter { !$0.passed } }
    public func claims(for axis: Axis) -> [Claim] {
        claims.filter { $0.axis == axis }
    }

    public func signoffClaims(for axis: Axis) -> [Claim] {
        claims.filter { $0.axis == axis && $0.kind == .signoff }
    }

    public func supportingClaims(for axis: Axis) -> [Claim] {
        claims.filter { $0.axis == axis && $0.kind == .supportingEvidence }
    }

    public func claim(_ axis: Axis) -> Claim? {
        let axisClaims = signoffClaims(for: axis)
        guard let first = axisClaims.first else { return nil }
        guard axisClaims.count > 1 else { return first }
        return Claim(
            axis: axis,
            statement: "\(axis.rawValue) axis aggregate",
            passed: axisClaims.allSatisfy(\.passed),
            measured: axisClaims.map { "\($0.statement): \($0.measured)" }.joined(separator: "; "),
            artifact: nil,
            kind: .signoff
        )
    }

    /// Machine-check the bundle: every `requiredAxes` signoff claim is present and passed, and
    /// every backing artifact verifies against its recorded digest. Supporting evidence is
    /// audited, but it never satisfies a required signoff axis.
    public func verify(
        requiredAxes: [Axis] = Self.defaultRequiredAxes,
        runDirectory: URL? = nil,
        requireArtifacts: Bool = true
    ) throws {
        guard !claims.isEmpty else { throw VerificationError.noClaims }
        let present = Set(claims.filter { $0.kind == .signoff }.map(\.axis))
        for axis in requiredAxes where !present.contains(axis) {
            throw VerificationError.missingAxis(axis)
        }
        for claim in claims {
            guard claim.passed else { throw VerificationError.claimFailed(axis: claim.axis, statement: claim.statement) }
            if requireArtifacts {
                guard let artifact = claim.artifact else {
                    throw VerificationError.missingArtifactReference(
                        axis: claim.axis,
                        statement: claim.statement
                    )
                }
                guard let runDirectory else {
                    throw VerificationError.artifactRunDirectoryRequired(axis: claim.axis, path: artifact.path)
                }
                do {
                    _ = try ArtifactIntegrityChecker().verifiedData(for: artifact, in: runDirectory)
                } catch {
                    throw VerificationError.artifactIntegrityFailed(
                        axis: claim.axis,
                        path: artifact.path,
                        reason: error.localizedDescription
                    )
                }
            }
        }
    }

    /// The bundle as a JSON manifest (the standard-format, portable record of the signoff).
    public func jsonManifest() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

extension TapeoutEvidenceBundle {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case designName
        case targetClockPeriod
        case claims
        case gdsPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported tapeout evidence schema version \(decodedSchemaVersion)."
            )
        }

        designName = try container.decode(String.self, forKey: .designName)
        targetClockPeriod = try container.decodeIfPresent(Double.self, forKey: .targetClockPeriod)
        gdsPath = try container.decodeIfPresent(String.self, forKey: .gdsPath)
        schemaVersion = decodedSchemaVersion
        claims = try container.decode([Claim].self, forKey: .claims)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(designName, forKey: .designName)
        try container.encodeIfPresent(targetClockPeriod, forKey: .targetClockPeriod)
        try container.encode(claims, forKey: .claims)
        try container.encodeIfPresent(gdsPath, forKey: .gdsPath)
    }
}
