import Foundation

/// The verifiable provenance of a closed design: every claim the flow makes — functional,
/// timing, DRC, LVS — paired with the measurement and a link to the REAL tool artifact that
/// backs it. A human (or CI) does not re-run the flow to trust it; they run `verify()`, which
/// re-checks that every claim passed AND its backing artifact still exists on disk. This is
/// the "evidence bundle" the goal requires — trust by machine-checkable evidence, never by a
/// silent pass.
public struct TapeoutEvidenceBundle: Sendable, Codable, Hashable {

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
        public let axis: Axis
        public let statement: String    // the asserted property
        public let passed: Bool
        public let measured: String     // the measured value / result
        public let artifact: String?    // path to the backing tool output or data file

        public init(axis: Axis, statement: String, passed: Bool, measured: String, artifact: String?) {
            self.axis = axis; self.statement = statement; self.passed = passed
            self.measured = measured; self.artifact = artifact
        }
    }

    public enum VerificationError: Error, LocalizedError, Equatable {
        case noClaims
        case missingAxis(Axis)
        case claimFailed(axis: Axis, statement: String)
        case artifactMissing(axis: Axis, path: String)

        public var errorDescription: String? {
            switch self {
            case .noClaims: return "The evidence bundle has no claims."
            case .missingAxis(let a): return "The bundle is missing the required \(a.rawValue) axis."
            case .claimFailed(let a, let s): return "Claim failed (\(a.rawValue)): \(s)."
            case .artifactMissing(let a, let p): return "Backing artifact for \(a.rawValue) is missing: \(p)."
            }
        }
    }

    public let designName: String
    public let targetClockPeriod: Double?
    public let claims: [Claim]
    public let gdsPath: String?

    public init(designName: String, targetClockPeriod: Double?, claims: [Claim], gdsPath: String?) {
        self.designName = designName
        self.targetClockPeriod = targetClockPeriod
        self.claims = claims
        self.gdsPath = gdsPath
    }

    public var passed: Bool { !claims.isEmpty && claims.allSatisfy(\.passed) }
    public var failing: [Claim] { claims.filter { !$0.passed } }
    public func claims(for axis: Axis) -> [Claim] {
        claims.filter { $0.axis == axis }
    }

    public func claim(_ axis: Axis) -> Claim? {
        let axisClaims = claims(for: axis)
        guard let first = axisClaims.first else { return nil }
        guard axisClaims.count > 1 else { return first }
        return Claim(
            axis: axis,
            statement: "\(axis.rawValue) axis aggregate",
            passed: axisClaims.allSatisfy(\.passed),
            measured: axisClaims.map { "\($0.statement): \($0.measured)" }.joined(separator: "; "),
            artifact: nil
        )
    }

    /// Machine-check the bundle: every `requiredAxes` claim is present and passed, and every
    /// claim that names a backing artifact still has that file on disk. Throws on the first
    /// problem (never a silent pass), so a passing `verify()` is a trustworthy signoff.
    public func verify(
        requiredAxes: [Axis] = [.functional, .timing, .drc, .lvs],
        fileManager: FileManager = .default,
        requireArtifacts: Bool = true
    ) throws {
        guard !claims.isEmpty else { throw VerificationError.noClaims }
        let present = Set(claims.map(\.axis))
        for axis in requiredAxes where !present.contains(axis) {
            throw VerificationError.missingAxis(axis)
        }
        for claim in claims {
            guard claim.passed else { throw VerificationError.claimFailed(axis: claim.axis, statement: claim.statement) }
            if requireArtifacts, let path = claim.artifact, !fileManager.fileExists(atPath: path) {
                throw VerificationError.artifactMissing(axis: claim.axis, path: path)
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
