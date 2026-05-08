import Foundation

public struct TechnologyPackageManifest: Sendable, Hashable, Codable {
    public struct LayoutTechnologyReference: Sendable, Hashable, Codable {
        public enum Kind: String, Sendable, Hashable, Codable {
            case builtin
            case json
        }

        public var kind: Kind
        public var id: String?
        public var path: String?

        public init(kind: Kind, id: String? = nil, path: String? = nil) {
            self.kind = kind
            self.id = id
            self.path = path
        }
    }

    public struct SignoffReference: Sendable, Hashable, Codable {
        public struct Tool: Sendable, Hashable, Codable {
            public var toolName: String
            public var executablePath: String?
            public var arguments: [String]
            public var replayLogPath: String?
            public var expectedSuccess: Bool

            public init(
                toolName: String,
                executablePath: String? = nil,
                arguments: [String] = [],
                replayLogPath: String? = nil,
                expectedSuccess: Bool = true
            ) {
                self.toolName = toolName
                self.executablePath = executablePath
                self.arguments = arguments
                self.replayLogPath = replayLogPath
                self.expectedSuccess = expectedSuccess
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.toolName = try container.decode(String.self, forKey: .toolName)
                self.executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath)
                self.arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
                self.replayLogPath = try container.decodeIfPresent(String.self, forKey: .replayLogPath)
                self.expectedSuccess = try container.decodeIfPresent(Bool.self, forKey: .expectedSuccess) ?? true
            }
        }

        public var adapterID: String
        public var drc: Tool?
        public var lvs: Tool?

        public init(adapterID: String, drc: Tool? = nil, lvs: Tool? = nil) {
            self.adapterID = adapterID
            self.drc = drc
            self.lvs = lvs
        }
    }

    public struct PEXReference: Sendable, Hashable, Codable {
        public var backendID: String?
        public var executablePath: String?
        public var projectConfigPath: String?
        public var savedManifestPath: String?
        public var defaultCornerID: String?

        public init(
            backendID: String? = nil,
            executablePath: String? = nil,
            projectConfigPath: String? = nil,
            savedManifestPath: String? = nil,
            defaultCornerID: String? = nil
        ) {
            self.backendID = backendID
            self.executablePath = executablePath
            self.projectConfigPath = projectConfigPath
            self.savedManifestPath = savedManifestPath
            self.defaultCornerID = defaultCornerID
        }
    }

    public struct CorpusReference: Sendable, Hashable, Codable {
        public var goldenLayoutManifestPath: String?

        public init(goldenLayoutManifestPath: String? = nil) {
            self.goldenLayoutManifestPath = goldenLayoutManifestPath
        }
    }

    public struct CornerReference: Sendable, Hashable, Codable {
        public var id: String
        public var processCornerID: UUID?
        public var pexCornerID: String?

        public init(id: String, processCornerID: UUID? = nil, pexCornerID: String? = nil) {
            self.id = id
            self.processCornerID = processCornerID
            self.pexCornerID = pexCornerID
        }
    }

    public var version: Int
    public var packageID: String
    public var name: String
    public var processTechnologyPath: String?
    public var spiceModelSearchPaths: [String]
    public var layoutTechnology: LayoutTechnologyReference?
    public var layerMapPath: String?
    public var signoff: SignoffReference?
    public var pex: PEXReference?
    public var corpus: CorpusReference?
    public var corners: [CornerReference]

    public init(
        version: Int = 1,
        packageID: String,
        name: String,
        processTechnologyPath: String? = nil,
        spiceModelSearchPaths: [String] = [],
        layoutTechnology: LayoutTechnologyReference? = nil,
        layerMapPath: String? = nil,
        signoff: SignoffReference? = nil,
        pex: PEXReference? = nil,
        corpus: CorpusReference? = nil,
        corners: [CornerReference] = []
    ) {
        self.version = version
        self.packageID = packageID
        self.name = name
        self.processTechnologyPath = processTechnologyPath
        self.spiceModelSearchPaths = spiceModelSearchPaths
        self.layoutTechnology = layoutTechnology
        self.layerMapPath = layerMapPath
        self.signoff = signoff
        self.pex = pex
        self.corpus = corpus
        self.corners = corners
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.packageID = try container.decode(String.self, forKey: .packageID)
        self.name = try container.decode(String.self, forKey: .name)
        self.processTechnologyPath = try container.decodeIfPresent(String.self, forKey: .processTechnologyPath)
        self.spiceModelSearchPaths = try container.decodeIfPresent([String].self, forKey: .spiceModelSearchPaths) ?? []
        self.layoutTechnology = try container.decodeIfPresent(LayoutTechnologyReference.self, forKey: .layoutTechnology)
        self.layerMapPath = try container.decodeIfPresent(String.self, forKey: .layerMapPath)
        self.signoff = try container.decodeIfPresent(SignoffReference.self, forKey: .signoff)
        self.pex = try container.decodeIfPresent(PEXReference.self, forKey: .pex)
        self.corpus = try container.decodeIfPresent(CorpusReference.self, forKey: .corpus)
        self.corners = try container.decodeIfPresent([CornerReference].self, forKey: .corners) ?? []
    }
}
