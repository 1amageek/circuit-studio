import Foundation
import PEXEngine

/// Persisted PEX configuration shared between CircuitStudio and the standalone `pexengine` CLI.
public struct PEXProjectConfig: Sendable, Codable, Hashable {
    public struct InputPaths: Sendable, Codable, Hashable {
        public var layout: String
        public var netlist: String
        public var technology: String
        public var technologyByCorner: [String: String]

        public init(
            layout: String = "top.oas",
            netlist: String = "top.cir",
            technology: String = "tech.json",
            technologyByCorner: [String: String] = [:]
        ) {
            self.layout = layout
            self.netlist = netlist
            self.technology = technology
            self.technologyByCorner = technologyByCorner
        }

        private enum CodingKeys: String, CodingKey {
            case layout
            case netlist
            case technology
            case technologyByCorner
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                layout: try container.decodeIfPresent(String.self, forKey: .layout) ?? "top.oas",
                netlist: try container.decodeIfPresent(String.self, forKey: .netlist) ?? "top.cir",
                technology: try container.decodeIfPresent(String.self, forKey: .technology) ?? "tech.json",
                technologyByCorner: try container.decodeIfPresent(
                    [String: String].self,
                    forKey: .technologyByCorner
                ) ?? [:]
            )
        }
    }

    public struct OutputPaths: Sendable, Codable, Hashable {
        public var workspace: String

        public init(workspace: String = ".xcircuite/pex/runs") {
            self.workspace = workspace
        }
    }

    public struct Options: Sendable, Codable, Hashable {
        public var includeCouplingCaps: Bool
        public var minCapacitanceF: Double?
        public var minResistanceOhm: Double?
        public var maxParallelJobs: Int
        public var strictValidation: Bool

        public init(
            includeCouplingCaps: Bool = true,
            minCapacitanceF: Double? = nil,
            minResistanceOhm: Double? = nil,
            maxParallelJobs: Int = 2,
            strictValidation: Bool = true
        ) {
            self.includeCouplingCaps = includeCouplingCaps
            self.minCapacitanceF = minCapacitanceF
            self.minResistanceOhm = minResistanceOhm
            self.maxParallelJobs = maxParallelJobs
            self.strictValidation = strictValidation
        }
    }

    public var version: Int
    public var enabled: Bool
    public var executablePath: String?
    public var topCell: String
    public var backendID: String
    public var corners: [String]
    public var processProfile: PEXProcessProfileReference?
    public var inputs: InputPaths
    public var output: OutputPaths
    public var options: Options

    public init(
        version: Int = 1,
        enabled: Bool = true,
        executablePath: String? = nil,
        topCell: String = "TOP",
        backendID: String = "",
        corners: [String] = ["tt_25c_1v0"],
        processProfile: PEXProcessProfileReference? = nil,
        inputs: InputPaths = InputPaths(),
        output: OutputPaths = OutputPaths(),
        options: Options = Options()
    ) {
        self.version = version
        self.enabled = enabled
        self.executablePath = executablePath
        self.topCell = topCell
        self.backendID = backendID
        self.corners = corners
        self.processProfile = processProfile
        self.inputs = inputs
        self.output = output
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath)
        self.topCell = try container.decodeIfPresent(String.self, forKey: .topCell) ?? "TOP"
        self.backendID = try container.decodeIfPresent(String.self, forKey: .backendID) ?? ""
        self.corners = try container.decodeIfPresent([String].self, forKey: .corners) ?? ["tt_25c_1v0"]
        self.processProfile = try container.decodeIfPresent(
            PEXProcessProfileReference.self,
            forKey: .processProfile
        )
        self.inputs = try container.decodeIfPresent(InputPaths.self, forKey: .inputs) ?? InputPaths()
        self.output = try container.decodeIfPresent(OutputPaths.self, forKey: .output) ?? OutputPaths()
        self.options = try container.decodeIfPresent(Options.self, forKey: .options) ?? Options()
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case enabled
        case executablePath
        case topCell
        case backendID
        case corners
        case processProfile
        case inputs
        case output
        case options
    }

    public var normalizedCorners: [String] {
        let filtered = corners.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if filtered.isEmpty {
            return ["tt_25c_1v0"]
        }
        return filtered
    }

    public var normalizedBackendID: String? {
        let trimmed = backendID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var usesMockBackend: Bool {
        guard let normalizedBackendID else {
            return false
        }
        return normalizedBackendID.lowercased().hasPrefix("mock")
    }
}
