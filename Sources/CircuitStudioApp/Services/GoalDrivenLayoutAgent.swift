import Foundation
import CircuitPhysicalDesign
import LayoutCore
import LayoutTech
import LayoutEditor
import LayoutVerify
import LayoutIO

/// C5: the agent end of the editor's goal-command surface. Given a
/// `.subckt` intent, this agent drives a `LayoutEditorViewModel` through
/// the SAME goal commands a human keymap issues — place, bind, finish,
/// repair — and gates the outcome on the editor's trust report, the live
/// LVS verdict, and goal-log replay determinism. Every step is recorded;
/// the result is an auditable evidence value plus a GDS artifact whose
/// net labels make it independently re-verifiable after reimport (the
/// dogfooded round-trip contract).
///
/// External Magic/Netgen signoff applies to the artifact when the
/// document's tech matches the external deck's layer names; the evidence
/// carries the GDS URL so a signoff loop can consume it as a candidate.
@MainActor
public struct GoalDrivenLayoutAgent {

    /// The auditable outcome of one closed intent.
    public struct Evidence {
        /// The goal commands actually executed, in order — a replayable
        /// script.
        public let script: [LayoutGoalCommand]
        /// The per-command verdict records around each executed command.
        public let goalLog: [LayoutGoalRecord]
        /// The editor's whole-picture verdict at close. (Qualified: the
        /// app layer has its own artifact type of the same name.)
        public let trustReport: LayoutEditor.LayoutTrustReport
        /// Replaying `script` on a fresh editor reproduced the same
        /// records and the same verdicts.
        public let replayDeterministic: Bool
        /// The exported, label-carrying GDS artifact.
        public let gdsURL: URL

        /// The closure claim: wired, clean, matching the intent, and
        /// reproducible. Constraint/electrical axes are reported but do
        /// not gate — absence of those checks is stated, not silently
        /// passed.
        public var closed: Bool {
            replayDeterministic
                && trustReport.drc == .clean
                && trustReport.connectivity == .clean
                && trustReport.lvs == .clean
        }
    }

    public enum AgentError: Error, LocalizedError, Equatable {
        case noIntentDevices
        case placementFailed(String)
        case bindingFailed
        case wiringIncomplete(opens: Int, detail: String)
        case violationsRemain(Int)
        case lvsFailed(String)
        case replayDiverged

        public var errorDescription: String? {
            switch self {
            case .noIntentDevices:
                return "The intent contains no devices to realize."
            case .placementFailed(let id):
                return "Placing intent device '\(id)' failed."
            case .bindingFailed:
                return "Binding intent terminals to reference nets failed."
            case .wiringIncomplete(let opens, let detail):
                return "finish-net left \(opens) open net(s): \(detail)"
            case .violationsRemain(let count):
                return "Repair left \(count) violation(s)."
            case .lvsFailed(let detail):
                return "The wired layout does not match the intent: \(detail)"
            case .replayDiverged:
                return "Replaying the goal script on a fresh editor diverged from the recorded log."
            }
        }
    }

    private let designName: String
    private let tech: LayoutTechDatabase
    /// Horizontal routing corridor between placed devices, in microns.
    private let placementMargin: Double

    public init(designName: String, tech: LayoutTechDatabase, placementMargin: Double = 2.0) {
        self.designName = designName
        self.tech = tech
        self.placementMargin = placementMargin
    }

    /// Drives a fresh editor from `.subckt` intent to a wired, DRC-clean,
    /// LVS-passing layout through goal commands only, verifies the goal
    /// log replays deterministically on a second fresh editor, labels
    /// every named net so the artifact survives GDS (where pins and nets
    /// die by contract), and exports it. Throws with the failing stage —
    /// never returns a half-closed artifact.
    public func close(intent subckt: String, exportDirectory: URL) throws -> Evidence {
        let editor = makeEditor(intent: subckt)
        let devices = editor.unplacedIntentDevices
        guard !devices.isEmpty else { throw AgentError.noIntentDevices }

        // Plan: one row, each device advanced by its cell width plus a
        // routing corridor. Reference order keeps the plan deterministic.
        var cursor = 0.0
        for device in devices {
            guard editor.execute(.placeIntentDevice(deviceID: device.id, at: LayoutPoint(x: cursor, y: 0))) else {
                throw AgentError.placementFailed(device.id)
            }
            cursor += placedCellWidth(editor: editor, instanceName: device.id) + placementMargin
        }

        guard editor.execute(.bindIntentTerminals) else {
            throw AgentError.bindingFailed
        }

        // Route on the layer the device terminals actually live on — the
        // editor's default active layer is whatever the tech lists
        // first, which may not even be a wiring layer. Selected through
        // a goal command so the replayed script carries the choice.
        if let cellID = editor.activeCellID,
           let cell = editor.editor.document.cell(withID: cellID),
           let instance = cell.instances.first,
           let child = editor.editor.document.cell(withID: instance.cellID),
           let terminalLayer = child.pins.first?.layer {
            editor.execute(.setActiveLayer(terminalLayer))
        }

        if editor.connectivityAnalysis?.opens.isEmpty == false {
            editor.execute(.finishAllNets)
        }
        let remainingOpens = editor.connectivityAnalysis?.opens ?? []
        guard remainingOpens.isEmpty else {
            var netNames: [String] = []
            if let cellID = editor.activeCellID,
               let cell = editor.editor.document.cell(withID: cellID) {
                let namesByID = Dictionary(
                    cell.nets.map { ($0.id, $0.name) },
                    uniquingKeysWith: { first, _ in first }
                )
                netNames = remainingOpens.map { namesByID[$0.netID] ?? $0.netID.uuidString }
            }
            throw AgentError.wiringIncomplete(
                opens: remainingOpens.count,
                detail: "open nets [\(netNames.joined(separator: ", "))]: "
                    + (editor.lastError ?? "no surfaced reason")
            )
        }

        if !editor.violations.isEmpty {
            editor.execute(.fixAllViolations)
        }
        guard editor.violations.isEmpty else {
            throw AgentError.violationsRemain(editor.violations.count)
        }

        guard editor.liveLVSPassed == true else {
            throw AgentError.lvsFailed(String(describing: editor.lvsComparison))
        }

        // Determinism gate: the same script on a fresh editor must
        // reproduce the same records and the same verdicts.
        let script = editor.goalLog.map(\.command)
        let replayed = makeEditor(intent: subckt)
        let replaySucceeded = replayed.replay(script)
        let replayDeterministic = replaySucceeded
            && replayed.goalLog == editor.goalLog
            && replayed.liveLVSPassed == true
            && replayed.violations.isEmpty
        guard replayDeterministic else { throw AgentError.replayDiverged }

        // Label every named net at one of its bound terminals so the
        // exported GDS carries the net identity that pins and nets lose
        // by format contract — extraction reads the labels back.
        labelNamedNets(editor: editor)

        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let gdsURL = exportDirectory.appendingPathComponent("\(Self.artifactFileStem(for: designName)).gds")
        try GDSFormatConverter(tech: tech).exportDocument(editor.editor.document, to: gdsURL, format: .gds)

        return Evidence(
            script: script,
            goalLog: editor.goalLog,
            trustReport: editor.trustReport,
            replayDeterministic: replayDeterministic,
            gdsURL: gdsURL
        )
    }

    // MARK: - Internals

    private func makeEditor(intent subckt: String) -> LayoutEditorViewModel {
        let top = LayoutCell(name: designName)
        let document = LayoutDocument(name: designName, cells: [top], topCellID: top.id)
        let editor = LayoutEditorViewModel(document: document, tech: tech)
        editor.loadLVSReference(fromSubckt: subckt)
        return editor
    }

    /// Width of the device cell the named instance realizes, for row
    /// placement. A missing instance contributes only the margin — the
    /// placement gate right after will report the failure.
    private func placedCellWidth(editor: LayoutEditorViewModel, instanceName: String) -> Double {
        guard let cellID = editor.activeCellID,
              let cell = editor.editor.document.cell(withID: cellID),
              let instance = cell.instances.first(where: { $0.name == instanceName }),
              let child = editor.editor.document.cell(withID: instance.cellID) else {
            return 0
        }
        let boxes = child.shapes.map { LayoutGeometryAnalysis.boundingBox(for: $0.geometry) }
        guard var union = boxes.first else { return 0 }
        for box in boxes.dropFirst() {
            union = union.union(box)
        }
        return union.size.width
    }

    private func labelNamedNets(editor: LayoutEditorViewModel) {
        guard let cellID = editor.activeCellID,
              let cell = editor.editor.document.cell(withID: cellID) else { return }
        let pins = editor.flattenedDocumentPins()
        for net in cell.nets.sorted(by: { $0.name < $1.name }) {
            guard let pin = pins.first(where: { $0.netID == net.id }) else { continue }
            editor.activeLayer = pin.layer
            editor.addLabel(text: net.name, at: pin.position)
        }
    }

    private static func artifactFileStem(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let stem = String(trimmed.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        })
        guard !stem.isEmpty, stem != ".", stem != ".." else {
            return "layout"
        }
        return stem
    }
}
