import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore
import LayoutCore
import LayoutIO
import LayoutTech
import LayoutVerify

@Suite("PhysicalVerificationService Tests")
struct PhysicalVerificationServiceTests {

    @Test func drcReportSummarizesViolationsByKind() {
        let service = PhysicalVerificationService()
        let violations = [
            LayoutViolation(kind: .minWidth, message: "M1 width"),
            LayoutViolation(kind: .minWidth, message: "M2 width"),
            LayoutViolation(kind: .disconnectedOpen, message: "Open net"),
        ]

        let report = service.makeDRCReport(violations: violations)

        #expect(!report.passed)
        #expect(report.violationCount == 3)
        #expect(report.violationsByKind["minWidth"] == 2)
        #expect(report.violationsByKind["disconnectedOpen"] == 1)
    }

    @Test func physicalRuleViolationsExcludeAnnotationScopeOpensOnly() {
        let result = LayoutDRCResult(violations: [
            LayoutViolation(kind: .minWidth, message: "M1 width"),
            LayoutViolation(kind: .disconnectedOpen, message: "Open net"),
            LayoutViolation(kind: .minSpacing, message: "M1 spacing"),
        ])

        let filtered = PhysicalVerificationService.physicalRuleViolations(in: result)

        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.kind != .disconnectedOpen })
    }

    @Test func lvsPassesWhenPhysicalInstancesAndNetsMatchDesignUnit() {
        let schematic = makeTwoResistorSchematic()
        let r1InstanceID = UUID()
        let r2InstanceID = UUID()
        let netID = UUID()
        let layout = makeLayoutDocument(instanceIDs: [r1InstanceID, r2InstanceID], netID: netID)
        let designUnit = DesignUnit(
            componentToInstance: [
                schematic.components[0].id: r1InstanceID,
                schematic.components[1].id: r2InstanceID,
            ],
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .standard()
        )

        #expect(report.passed)
        #expect(report.schematicHashMatches)
        #expect(report.missingLayoutInstances.isEmpty)
        #expect(report.extraLayoutInstances.isEmpty)
        #expect(report.missingLayoutNets.isEmpty)
        #expect(report.extraLayoutNets.isEmpty)
        #expect(report.danglingMappedInstanceIDs.isEmpty)
        #expect(report.danglingMappedNetIDs.isEmpty)
    }

    @Test func lvsReportsMissingInstancesNetsAndStaleHash() {
        let schematic = makeTwoResistorSchematic()
        let r1InstanceID = UUID()
        let extraNetID = UUID()
        let layout = makeLayoutDocument(instanceIDs: [r1InstanceID], netID: extraNetID)
        let designUnit = DesignUnit(
            componentToInstance: [schematic.components[0].id: r1InstanceID],
            netNameToLayoutNet: ["extra": extraNetID],
            schematicHash: 12345
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit
        )

        #expect(!report.passed)
        #expect(!report.schematicHashMatches)
        #expect(report.missingLayoutInstances == ["R2"])
        #expect(report.extraLayoutInstances.isEmpty)
        #expect(report.missingLayoutNets == ["net0"])
        #expect(report.extraLayoutNets == ["extra"])
        #expect(report.danglingMappedInstanceIDs.isEmpty)
        #expect(report.danglingMappedNetIDs.isEmpty)
    }

    @Test func lvsRejectsDanglingDesignUnitMappingsForEmptyLayout() {
        let schematic = makeTwoResistorSchematic()
        let layout = makeLayoutDocument()
        let designUnit = DesignUnit(
            componentToInstance: Dictionary(
                uniqueKeysWithValues: schematic.components.map { ($0.id, UUID()) }
            ),
            netNameToLayoutNet: ["net0": UUID()],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit
        )

        #expect(!report.passed)
        #expect(report.schematicHashMatches)
        #expect(report.missingLayoutInstances == ["R1", "R2"])
        #expect(report.extraLayoutInstances.isEmpty)
        #expect(report.missingLayoutNets == ["net0"])
        #expect(report.danglingMappedInstanceIDs.count == 2)
        #expect(report.danglingMappedNetIDs.count == 1)
    }

    @Test func lvsReportsExtraPhysicalInstancesAndNetsNotInDesignUnit() {
        let schematic = makeTwoResistorSchematic()
        let r1InstanceID = UUID()
        let r2InstanceID = UUID()
        let extraInstanceID = UUID()
        let netID = UUID()
        let extraNetID = UUID()
        let layout = makeLayoutDocument(
            instanceIDs: [r1InstanceID, r2InstanceID],
            extraInstanceIDs: [extraInstanceID],
            netID: netID,
            extraNetIDs: [extraNetID]
        )
        let designUnit = DesignUnit(
            componentToInstance: [
                schematic.components[0].id: r1InstanceID,
                schematic.components[1].id: r2InstanceID,
            ],
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit
        )

        #expect(!report.passed)
        #expect(report.extraLayoutInstances == ["EXTRA0"])
        #expect(report.extraLayoutNets == ["extra0"])
        #expect(report.missingLayoutInstances.isEmpty)
        #expect(report.missingLayoutNets.isEmpty)
    }

    @Test func lvsRejectsDeclaredNetWithoutPhysicalGeometry() {
        let schematic = makeTwoResistorSchematic()
        let r1InstanceID = UUID()
        let r2InstanceID = UUID()
        let netID = UUID()
        let layout = makeLayoutDocument(
            instanceIDs: [r1InstanceID, r2InstanceID],
            netID: netID,
            includeNetGeometry: false
        )
        let designUnit = DesignUnit(
            componentToInstance: [
                schematic.components[0].id: r1InstanceID,
                schematic.components[1].id: r2InstanceID,
            ],
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit
        )

        #expect(!report.passed)
        #expect(report.missingLayoutInstances.isEmpty)
        #expect(report.missingLayoutNets == ["net0"])
        #expect(report.danglingMappedNetIDs == [netID])
    }

    @Test func prePEXVerificationRequiresBothDRCAndLVS() {
        let schematic = makeTwoResistorSchematic()
        let r1InstanceID = UUID()
        let r2InstanceID = UUID()
        let netID = UUID()
        let layout = makeLayoutDocument(instanceIDs: [r1InstanceID, r2InstanceID], netID: netID)
        let designUnit = DesignUnit(
            componentToInstance: [
                schematic.components[0].id: r1InstanceID,
                schematic.components[1].id: r2InstanceID,
            ],
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runPrePEXVerification(
            schematic: schematic,
            layout: layout,
            tech: .standard(),
            designUnit: designUnit
        )

        #expect(report.lvs.passed)
        #expect(report.drc.passed)
        #expect(report.isReadyForPEX)
    }

    @Test func prePEXVerificationRequiresExternalSignoffApproval() {
        let schematic = makeTwoResistorSchematic()
        let r1InstanceID = UUID()
        let r2InstanceID = UUID()
        let netID = UUID()
        let layout = makeLayoutDocument(instanceIDs: [r1InstanceID, r2InstanceID], netID: netID)
        let designUnit = DesignUnit(
            componentToInstance: [
                schematic.components[0].id: r1InstanceID,
                schematic.components[1].id: r2InstanceID,
            ],
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )
        let signoff = makeCleanExternalSignoffReview()

        let report = PhysicalVerificationService().runPrePEXVerification(
            schematic: schematic,
            layout: layout,
            tech: .standard(),
            designUnit: designUnit,
            externalSignoff: signoff
        )

        #expect(report.drc.passed)
        #expect(report.lvs.passed)
        #expect(report.externalSignoff?.passed == true)
        #expect(report.externalSignoff?.isApproved == false)
        #expect(!report.isReadyForPEX)
    }

    @Test func prePEXVerificationAcceptsApprovedExternalSignoff() {
        let schematic = makeTwoResistorSchematic()
        let r1InstanceID = UUID()
        let r2InstanceID = UUID()
        let netID = UUID()
        let layout = makeLayoutDocument(instanceIDs: [r1InstanceID, r2InstanceID], netID: netID)
        let designUnit = DesignUnit(
            componentToInstance: [
                schematic.components[0].id: r1InstanceID,
                schematic.components[1].id: r2InstanceID,
            ],
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )
        let signoff = makeCleanExternalSignoffReview(approvedBy: "layout-reviewer")

        let report = PhysicalVerificationService().runPrePEXVerification(
            schematic: schematic,
            layout: layout,
            tech: .standard(),
            designUnit: designUnit,
            externalSignoff: signoff
        )

        #expect(report.externalSignoff?.isReadyForPEX == true)
        #expect(report.isReadyForPEX)
    }

    @Test func externalSignoffErrorsBlockPEXEvenWhenApproved() {
        let rawOutput = "[ERROR] rule=LVS_SHORT component=MN1 net=out message=\"layout short detected\""
        let lvsReport = ExternalSignoffReportParser().parse(
            kind: .lvs,
            toolName: "calibre",
            logPath: "/tmp/lvs.log",
            rawOutput: rawOutput,
            success: true
        )
        let signoff = ExternalSignoffReview(
            reports: [lvsReport],
            approvedBy: "layout-reviewer",
            approvedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(!lvsReport.passed)
        #expect(lvsReport.diagnostics == [
            ExternalSignoffDiagnostic(
                severity: .error,
                message: "layout short detected",
                ruleID: "LVS_SHORT",
                componentName: "MN1",
                netName: "out",
                rawLine: rawOutput
            ),
        ])
        #expect(!signoff.isReadyForPEX)
    }

    @Test func fullLVSReportsPhysicalShorts() {
        let schematic = makeTwoNetSchematic()
        let r1InstanceID = UUID()
        let r2InstanceID = UUID()
        let c1InstanceID = UUID()
        let c2InstanceID = UUID()
        let netAID = UUID()
        let netBID = UUID()
        let layout = makeTwoPinLayout(
            r1InstanceID: r1InstanceID,
            r2InstanceID: r2InstanceID,
            c1InstanceID: c1InstanceID,
            c2InstanceID: c2InstanceID,
            netAID: netAID,
            netBID: netBID,
            shortTogether: true
        )
        let designUnit = DesignUnit(
            componentToInstance: [
                schematic.components[0].id: r1InstanceID,
                schematic.components[1].id: r2InstanceID,
                schematic.components[2].id: c1InstanceID,
                schematic.components[3].id: c2InstanceID,
            ],
            netNameToLayoutNet: ["net0": netAID, "net1": netBID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .standard()
        )

        #expect(!report.passed)
        #expect(report.physicalShorts.count == 1)
        #expect(report.physicalShorts[0].netNames == ["net0", "net1"])
    }

    @Test func fullLVSReportsPhysicalOpens() {
        let schematic = makeTwoResistorSchematic()
        let r1InstanceID = UUID()
        let r2InstanceID = UUID()
        let netID = UUID()
        let layout = makeLayoutDocument(
            instanceIDs: [r1InstanceID, r2InstanceID],
            netID: netID,
            connectInstancePins: false
        )
        let designUnit = DesignUnit(
            componentToInstance: [
                schematic.components[0].id: r1InstanceID,
                schematic.components[1].id: r2InstanceID,
            ],
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .standard()
        )

        #expect(!report.passed)
        #expect(report.physicalOpens.count == 1)
        #expect(report.physicalOpens[0].netName == "net0")
        #expect(report.physicalOpens[0].physicalNetCount == 2)
    }

    @Test func fullLVSSkipsConnectivityWhenTechIsMissing() {
        let schematic = makeTwoResistorSchematic()
        let r1InstanceID = UUID()
        let r2InstanceID = UUID()
        let netID = UUID()
        let layout = makeLayoutDocument(instanceIDs: [r1InstanceID, r2InstanceID], netID: netID)
        let designUnit = DesignUnit(
            componentToInstance: [
                schematic.components[0].id: r1InstanceID,
                schematic.components[1].id: r2InstanceID,
            ],
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit
        )

        #expect(!report.passed)
        #expect(report.connectivityExtractionSkipped)
    }

    @Test func hierarchicalLVSFlattensWrapperCells() {
        let schematic = makeTwoResistorSchematic()
        let r1InstanceID = UUID()
        let r2InstanceID = UUID()
        let netID = UUID()
        let layout = makeHierarchicalLayout(
            r1InstanceID: r1InstanceID,
            r2InstanceID: r2InstanceID,
            netID: netID
        )
        let designUnit = DesignUnit(
            componentToInstance: [
                schematic.components[0].id: r1InstanceID,
                schematic.components[1].id: r2InstanceID,
            ],
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .standard()
        )

        #expect(report.passed)
        #expect(report.missingLayoutInstances.isEmpty)
        #expect(report.extraLayoutInstances.isEmpty)
        #expect(report.physicalOpens.isEmpty)
    }

    @Test func fullLVSRecognizesImportedPolygonTerminals() {
        let schematic = makeTwoResistorSchematic()
        let netID = UUID()
        let layout = makePolygonTerminalLayout(netID: netID)
        let designUnit = DesignUnit(
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .standard()
        )

        #expect(report.passed)
        #expect(report.missingLayoutInstances.isEmpty)
        #expect(report.physicalOpens.isEmpty)
        #expect(report.unconnectedLayoutPins.isEmpty)
    }

    @Test func fullLVSRequiresExternalPortForSinglePhysicalTerminalNet() {
        let schematic = makeResistorSourceSchematic()
        let r1InstanceID = UUID()
        let netID = UUID()
        let layout = makeSingleTerminalLayout(
            r1InstanceID: r1InstanceID,
            netID: netID,
            externalPinName: nil
        )
        let designUnit = DesignUnit(
            componentToInstance: [schematic.components[0].id: r1InstanceID],
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .standard()
        )

        #expect(!report.passed)
        #expect(report.missingExternalLayoutPorts == ["net0"])
    }

    @Test func fullLVSRejectsWrongExternalPortNameForSinglePhysicalTerminalNet() {
        let schematic = makeResistorSourceSchematic()
        let r1InstanceID = UUID()
        let netID = UUID()
        let layout = makeSingleTerminalLayout(
            r1InstanceID: r1InstanceID,
            netID: netID,
            externalPinName: "wrong"
        )
        let designUnit = DesignUnit(
            componentToInstance: [schematic.components[0].id: r1InstanceID],
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .standard()
        )

        #expect(!report.passed)
        #expect(report.missingExternalLayoutPorts == ["net0"])
    }

    @Test func fullLVSUsesHierarchicalLayoutNetNamesForTerminalMismatches() {
        let schematic = makeTwoResistorSchematic()
        let r1InstanceID = UUID()
        let r2InstanceID = UUID()
        let netID = UUID()
        let layout = makeHierarchicalLayout(
            r1InstanceID: r1InstanceID,
            r2InstanceID: r2InstanceID,
            netID: netID,
            layoutNetName: "wrong"
        )
        let designUnit = DesignUnit(
            componentToInstance: [
                schematic.components[0].id: r1InstanceID,
                schematic.components[1].id: r2InstanceID,
            ],
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .standard()
        )

        #expect(!report.passed)
        #expect(!report.terminalMismatches.isEmpty)
    }

    @Test func fullLVSRejectsInvalidImportedPolygonTerminals() {
        let schematic = makeTwoResistorSchematic()
        let netID = UUID()
        let layout = makePolygonTerminalLayout(
            netID: netID,
            firstTerminalProperties: ["lvs.component": "UNKNOWN", "lvs.pin": "pos"]
        )
        let designUnit = DesignUnit(
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .standard()
        )

        #expect(!report.passed)
        #expect(report.invalidLayoutTerminals == [
            LVSVerificationReport.Terminal(componentName: "UNKNOWN", pinName: "pos"),
        ])
    }

    @Test func fullLVSRejectsDuplicateImportedPolygonTerminalsAcrossClusters() {
        let schematic = makeTwoResistorSchematic()
        let netID = UUID()
        let duplicateNetID = UUID()
        let layout = makePolygonDuplicateTerminalLayout(netID: netID, duplicateNetID: duplicateNetID)
        let designUnit = DesignUnit(
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .standard()
        )

        #expect(!report.passed)
        #expect(report.duplicateLayoutTerminals == [
            LVSVerificationReport.Terminal(componentName: "R1", pinName: "pos"),
        ])
    }

    @Test func rawMOSLVSRecognizesDeviceAndParametersWithoutMetadata() {
        let schematic = makeSingleNMOSSchematic(width: 10e-6, length: 1e-6)
        let layout = makeRawMOSLayout(name: "MN1", width: 10, length: 1)
        let designUnit = DesignUnit(schematicHash: DesignUnit.schematicHash(for: schematic))

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(report.passed)
        #expect(report.missingLayoutInstances.isEmpty)
        #expect(report.deviceParameterMismatches.isEmpty)
    }

    @Test func rawMOSLVSRejectsParameterMismatch() {
        let schematic = makeSingleNMOSSchematic(width: 10e-6, length: 1e-6)
        let layout = makeRawMOSLayout(name: "MN1", width: 12, length: 1)
        let designUnit = DesignUnit(schematicHash: DesignUnit.schematicHash(for: schematic))

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(!report.passed)
        #expect(report.deviceParameterMismatches.map(\.parameterName) == ["w"])
    }

    @Test func rawMOSLVSRejectsDuplicateDeviceNames() {
        let schematic = makeSingleNMOSSchematic(width: 10e-6, length: 1e-6)
        let layout = makeRawMOSLayout(name: "MN1", width: 10, length: 1, duplicate: true)
        let designUnit = DesignUnit(schematicHash: DesignUnit.schematicHash(for: schematic))

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(!report.passed)
        #expect(report.duplicateLayoutDevices == ["MN1"])
    }

    @Test func rawMOSLVSRejectsDeviceKindMismatch() {
        let schematic = makeSinglePMOSSchematic(width: 10e-6, length: 1e-6)
        let layout = makeRawMOSLayout(name: "MP1", width: 10, length: 1, kind: .nmos)
        let designUnit = DesignUnit(schematicHash: DesignUnit.schematicHash(for: schematic))

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(!report.passed)
        #expect(report.deviceParameterMismatches.map(\.parameterName) == ["kind"])
    }

    @Test func rawMOSLVSConnectsExtractedDrainTerminals() {
        let schematic = makeTwoNMOSDrainSchematic()
        let netID = UUID()
        let layout = makeRawMOSConnectivityLayout(netID: netID, connectDrains: true)
        let designUnit = DesignUnit(
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(report.passed)
        #expect(report.missingLayoutInstances.isEmpty)
        #expect(report.physicalOpens.isEmpty)
    }

    @Test func rawMOSLVSReportsOpenExtractedDrainTerminals() {
        let schematic = makeTwoNMOSDrainSchematic()
        let netID = UUID()
        let layout = makeRawMOSConnectivityLayout(netID: netID, connectDrains: false)
        let designUnit = DesignUnit(
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(!report.passed)
        #expect(report.physicalOpens == [
            LVSVerificationReport.PhysicalOpen(
                netName: "net0",
                terminals: [
                    LVSVerificationReport.Terminal(componentName: "MN1", pinName: "drain"),
                    LVSVerificationReport.Terminal(componentName: "MN2", pinName: "drain"),
                ],
                physicalNetCount: 2
            ),
        ])
    }

    @Test func rawResistorLVSRecognizesResistanceWithoutMetadata() {
        let schematic = makeSingleResistorSchematic(resistance: 1000)
        let layout = makeRawResistorLayout(name: "R1", width: 2, length: 10)
        let designUnit = DesignUnit(schematicHash: DesignUnit.schematicHash(for: schematic))

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(report.passed)
        #expect(report.deviceParameterMismatches.isEmpty)
    }

    @Test func rawResistorLVSRejectsResistanceMismatch() {
        let schematic = makeSingleResistorSchematic(resistance: 1000)
        let layout = makeRawResistorLayout(name: "R1", width: 2, length: 12)
        let designUnit = DesignUnit(schematicHash: DesignUnit.schematicHash(for: schematic))

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(!report.passed)
        #expect(report.deviceParameterMismatches.map(\.parameterName) == ["r"])
    }

    @Test func rawCapacitorLVSRecognizesCapacitanceWithoutMetadata() {
        let capacitance = 8.6e-15 * 20
        let schematic = makeSingleCapacitorSchematic(capacitance: capacitance)
        let layout = makeRawCapacitorLayout(name: "C1", overlapWidth: 10, overlapHeight: 2)
        let designUnit = DesignUnit(schematicHash: DesignUnit.schematicHash(for: schematic))

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(report.passed)
        #expect(report.missingLayoutInstances.isEmpty)
        #expect(report.deviceParameterMismatches.isEmpty)
    }

    @Test func rawCapacitorLVSRejectsCapacitanceMismatch() {
        let schematic = makeSingleCapacitorSchematic(capacitance: 8.6e-15 * 25)
        let layout = makeRawCapacitorLayout(name: "C1", overlapWidth: 10, overlapHeight: 2)
        let designUnit = DesignUnit(schematicHash: DesignUnit.schematicHash(for: schematic))

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(!report.passed)
        #expect(report.deviceParameterMismatches.map(\.parameterName) == ["c"])
    }

    @Test(.timeLimit(.minutes(1)))
    func importedOASRawTopologyPassesStrictDRCAndLVS() throws {
        let schematic = makeImportedVoltageDividerSchematic()
        let sourceLayout = makeImportedVoltageDividerLayout()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "circuit-studio-imported-oas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                Issue.record("Failed to remove temporary directory: \(error)")
            }
        }

        let layoutURL = directory.appending(path: "voltage-divider.oas")
        let io = LayoutIOService(converter: MaskDataFormatConverter(tech: .sampleProcess()))
        try io.saveDocument(sourceLayout, to: layoutURL, format: .oasis)
        let importedLayout = try io.loadDocument(from: layoutURL, format: .oasis)
        let designUnit = DesignUnit(schematicHash: DesignUnit.schematicHash(for: schematic))

        let report = PhysicalVerificationService().runPrePEXVerification(
            schematic: schematic,
            layout: importedLayout,
            tech: .sampleProcess(),
            designUnit: designUnit
        )

        if !report.isReadyForPEX {
            Issue.record("DRC: \(report.drc)")
            Issue.record("LVS: \(report.lvs)")
        }

        #expect(report.drc.passed)
        #expect(report.lvs.passed)
        #expect(report.isReadyForPEX)
    }

    @Test func rawMOSLVSRecognizesMultiFingerParameters() {
        let schematic = makeSingleNMOSSchematic(width: 10e-6, length: 1e-6, fingerCount: 2)
        let layout = makeRawMOSLayout(name: "MN1", width: 10, length: 1, fingerCount: 2)
        let designUnit = DesignUnit(schematicHash: DesignUnit.schematicHash(for: schematic))

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(report.passed)
        #expect(report.duplicateLayoutDevices.isEmpty)
        #expect(report.deviceParameterMismatches.isEmpty)
    }

    @Test func fullLVSRejectsHierarchyCyclesBeforeExtraction() {
        let schematic = makeSingleResistorSchematic(resistance: 1000)
        let layout = makeHierarchyCycleLayout()
        let designUnit = DesignUnit(schematicHash: DesignUnit.schematicHash(for: schematic))

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .standard()
        )

        #expect(!report.passed)
        #expect(report.layoutTopologyErrors.contains { $0.contains("Hierarchy cycle") })
    }

    @Test func importedNumericLayerRawMOSLVSUsesTechnologyLayerAliases() {
        let schematic = makeTwoNMOSDrainSchematic()
        let netID = UUID()
        let layout = makeRawMOSConnectivityLayout(
            netID: netID,
            connectDrains: true,
            useNumericImportedLayers: true
        )
        let designUnit = DesignUnit(
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(report.passed)
        #expect(report.deviceParameterMismatches.isEmpty)
        #expect(report.physicalOpens.isEmpty)
    }

    @Test func importedCutShapeConnectsTerminalsAcrossProcessLayers() {
        let schematic = makeTwoResistorSchematic()
        let netID = UUID()
        let layout = makeImportedContactBridgeLayout(netID: netID)
        let designUnit = DesignUnit(
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(report.passed)
        #expect(report.physicalOpens.isEmpty)
    }

    @Test func sharedDiffusionRawMOSLVSRecognizesSeriesDevices() {
        let schematic = makeTwoNMOSSeriesSchematic()
        let netID = UUID()
        let layout = makeSharedDiffusionSeriesMOSLayout(netID: netID)
        let designUnit = DesignUnit(
            netNameToLayoutNet: ["net0": netID],
            schematicHash: DesignUnit.schematicHash(for: schematic)
        )

        let report = PhysicalVerificationService().runLVS(
            schematic: schematic,
            layout: layout,
            designUnit: designUnit,
            tech: .sampleProcess()
        )

        #expect(report.passed)
        #expect(report.duplicateLayoutDevices.isEmpty)
        #expect(report.physicalOpens.isEmpty)
    }

    private func makeTwoResistorSchematic() -> SchematicDocument {
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        let r2 = PlacedComponent(deviceKindID: "resistor", name: "R2", position: CGPoint(x: 100, y: 0))
        let wire = Wire(
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 100, y: 0),
            startPin: PinReference(componentID: r1.id, portID: "pos"),
            endPin: PinReference(componentID: r2.id, portID: "pos")
        )
        return SchematicDocument(components: [r1, r2], wires: [wire])
    }

    private func makeCleanExternalSignoffReview(approvedBy: String? = nil) -> ExternalSignoffReview {
        ExternalSignoffReview(
            reports: [
                ExternalSignoffToolReport(
                    kind: .drc,
                    toolName: "calibre",
                    success: true,
                    logPath: "/tmp/drc.log"
                ),
                ExternalSignoffToolReport(
                    kind: .lvs,
                    toolName: "calibre",
                    success: true,
                    logPath: "/tmp/lvs.log"
                ),
            ],
            approvedBy: approvedBy,
            approvedAt: approvedBy == nil ? nil : Date(timeIntervalSince1970: 0)
        )
    }

    private func makeTwoNetSchematic() -> SchematicDocument {
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        let r2 = PlacedComponent(deviceKindID: "resistor", name: "R2", position: CGPoint(x: 100, y: 0))
        let c1 = PlacedComponent(deviceKindID: "capacitor", name: "C1", position: CGPoint(x: 0, y: 100))
        let c2 = PlacedComponent(deviceKindID: "capacitor", name: "C2", position: CGPoint(x: 100, y: 100))
        let net0 = Wire(
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 100, y: 0),
            startPin: PinReference(componentID: r1.id, portID: "pos"),
            endPin: PinReference(componentID: r2.id, portID: "pos")
        )
        let net1 = Wire(
            startPoint: CGPoint(x: 0, y: 100),
            endPoint: CGPoint(x: 100, y: 100),
            startPin: PinReference(componentID: c1.id, portID: "pos"),
            endPin: PinReference(componentID: c2.id, portID: "pos")
        )
        return SchematicDocument(components: [r1, r2, c1, c2], wires: [net0, net1])
    }

    private func makeResistorSourceSchematic() -> SchematicDocument {
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        let v1 = PlacedComponent(deviceKindID: "vsource", name: "V1", position: CGPoint(x: 100, y: 0))
        let wire = Wire(
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 100, y: 0),
            startPin: PinReference(componentID: r1.id, portID: "pos"),
            endPin: PinReference(componentID: v1.id, portID: "pos")
        )
        return SchematicDocument(components: [r1, v1], wires: [wire])
    }

    private func makeSingleNMOSSchematic(width: Double, length: Double, fingerCount: Double? = nil) -> SchematicDocument {
        var parameters = ["w": width, "l": length]
        if let fingerCount {
            parameters["nf"] = fingerCount
        }
        return SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "nmos_l1",
                name: "MN1",
                position: .zero,
                parameters: parameters
            ),
        ])
    }

    private func makeSinglePMOSSchematic(width: Double, length: Double) -> SchematicDocument {
        SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "pmos_l1",
                name: "MP1",
                position: .zero,
                parameters: ["w": width, "l": length]
            ),
        ])
    }

    private func makeTwoNMOSDrainSchematic() -> SchematicDocument {
        let mn1 = PlacedComponent(
            deviceKindID: "nmos_l1",
            name: "MN1",
            position: .zero,
            parameters: ["w": 10e-6, "l": 1e-6]
        )
        let mn2 = PlacedComponent(
            deviceKindID: "nmos_l1",
            name: "MN2",
            position: CGPoint(x: 100, y: 0),
            parameters: ["w": 10e-6, "l": 1e-6]
        )
        let wire = Wire(
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 100, y: 0),
            startPin: PinReference(componentID: mn1.id, portID: "drain"),
            endPin: PinReference(componentID: mn2.id, portID: "drain")
        )
        return SchematicDocument(components: [mn1, mn2], wires: [wire])
    }

    private func makeTwoNMOSSeriesSchematic() -> SchematicDocument {
        let mn1 = PlacedComponent(
            deviceKindID: "nmos_l1",
            name: "MN1",
            position: .zero,
            parameters: ["w": 10e-6, "l": 1e-6]
        )
        let mn2 = PlacedComponent(
            deviceKindID: "nmos_l1",
            name: "MN2",
            position: CGPoint(x: 100, y: 0),
            parameters: ["w": 10e-6, "l": 1e-6]
        )
        let wire = Wire(
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 100, y: 0),
            startPin: PinReference(componentID: mn1.id, portID: "drain"),
            endPin: PinReference(componentID: mn2.id, portID: "source")
        )
        return SchematicDocument(components: [mn1, mn2], wires: [wire])
    }

    private func makeSingleResistorSchematic(resistance: Double) -> SchematicDocument {
        SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "resistor",
                name: "R1",
                position: .zero,
                parameters: ["r": resistance]
            ),
        ])
    }

    private func makeSingleCapacitorSchematic(capacitance: Double) -> SchematicDocument {
        SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "capacitor",
                name: "C1",
                position: .zero,
                parameters: ["c": capacitance]
            ),
        ])
    }

    private func makeImportedVoltageDividerSchematic() -> SchematicDocument {
        let v1 = PlacedComponent(deviceKindID: "vsource", name: "V1", position: CGPoint(x: 0, y: 0))
        let r1 = PlacedComponent(
            deviceKindID: "resistor",
            name: "R1",
            position: CGPoint(x: 100, y: 0),
            parameters: ["r": 1000]
        )
        let r2 = PlacedComponent(
            deviceKindID: "resistor",
            name: "R2",
            position: CGPoint(x: 200, y: 0),
            parameters: ["r": 1000]
        )
        let gnd = PlacedComponent(deviceKindID: "ground", name: "GND1", position: CGPoint(x: 300, y: 0))
        return SchematicDocument(
            components: [v1, r1, r2, gnd],
            wires: [
                Wire(
                    startPoint: .zero,
                    endPoint: CGPoint(x: 100, y: 0),
                    startPin: PinReference(componentID: v1.id, portID: "pos"),
                    endPin: PinReference(componentID: r1.id, portID: "neg"),
                    netName: "vin"
                ),
                Wire(
                    startPoint: CGPoint(x: 100, y: 50),
                    endPoint: CGPoint(x: 200, y: 50),
                    startPin: PinReference(componentID: r1.id, portID: "pos"),
                    endPin: PinReference(componentID: r2.id, portID: "neg"),
                    netName: "out"
                ),
                Wire(
                    startPoint: CGPoint(x: 200, y: 100),
                    endPoint: CGPoint(x: 300, y: 100),
                    startPin: PinReference(componentID: r2.id, portID: "pos"),
                    endPin: PinReference(componentID: gnd.id, portID: "gnd"),
                    netName: "0"
                ),
            ]
        )
    }

    private func makeLayoutDocument(
        instanceIDs: [UUID] = [],
        extraInstanceIDs: [UUID] = [],
        netID: UUID? = nil,
        extraNetIDs: [UUID] = [],
        includeNetGeometry: Bool = true,
        connectInstancePins: Bool = true
    ) -> LayoutDocument {
        let device = LayoutCell(name: "RES", pins: [
            LayoutPin(
                name: "pos",
                position: LayoutPoint(x: 0, y: 0),
                size: LayoutSize(width: 1, height: 1),
                layer: LayoutLayerID(name: "M1", purpose: "drawing")
            ),
            LayoutPin(
                name: "neg",
                position: LayoutPoint(x: 0, y: 5),
                size: LayoutSize(width: 1, height: 1),
                layer: LayoutLayerID(name: "M1", purpose: "drawing")
            ),
        ])
        let instances = instanceIDs.enumerated().map {
            LayoutInstance(
                id: $0.element,
                cellID: device.id,
                name: "R\($0.offset + 1)",
                transform: LayoutTransform(translation: LayoutPoint(x: Double($0.offset) * 10, y: 0))
            )
        } + extraInstanceIDs.enumerated().map {
            LayoutInstance(id: $0.element, cellID: device.id, name: "EXTRA\($0.offset)")
        }
        let nets = (netID.map { [LayoutNet(id: $0, name: "net0")] } ?? [])
            + extraNetIDs.enumerated().map { LayoutNet(id: $0.element, name: "extra\($0.offset)") }
        let shapes: [LayoutShape]
        if includeNetGeometry, let netID {
            shapes = connectInstancePins ? [
                LayoutShape(
                    layer: LayoutLayerID(name: "M1", purpose: "drawing"),
                    netID: netID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: -0.5, y: -0.5),
                        size: LayoutSize(width: 11, height: 1)
                    ))
                ),
            ] : [
                LayoutShape(
                    layer: LayoutLayerID(name: "M1", purpose: "drawing"),
                    netID: netID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: -0.5, y: -0.5),
                        size: LayoutSize(width: 1, height: 1)
                    ))
                ),
                LayoutShape(
                    layer: LayoutLayerID(name: "M1", purpose: "drawing"),
                    netID: netID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 9.5, y: -0.5),
                        size: LayoutSize(width: 1, height: 1)
                    ))
                ),
            ]
        } else {
            shapes = []
        }
        let top = LayoutCell(name: "TOP", shapes: shapes, instances: instances, nets: nets)
        return LayoutDocument(name: "Layout", cells: [device, top], topCellID: top.id)
    }

    private func makeTwoPinLayout(
        r1InstanceID: UUID,
        r2InstanceID: UUID,
        c1InstanceID: UUID,
        c2InstanceID: UUID,
        netAID: UUID,
        netBID: UUID,
        shortTogether: Bool
    ) -> LayoutDocument {
        let resistor = LayoutCell(name: "RES", pins: [
            LayoutPin(
                name: "pos",
                position: LayoutPoint(x: 0, y: 0),
                size: LayoutSize(width: 1, height: 1),
                layer: LayoutLayerID(name: "M1", purpose: "drawing")
            ),
        ])
        let capacitor = LayoutCell(name: "CAP", pins: [
            LayoutPin(
                name: "pos",
                position: LayoutPoint(x: 0, y: 0),
                size: LayoutSize(width: 1, height: 1),
                layer: LayoutLayerID(name: "M1", purpose: "drawing")
            ),
        ])
        let bridgeWidth = shortTogether ? 31.0 : 11.0
        let top = LayoutCell(
            name: "TOP",
            shapes: [
                LayoutShape(
                    layer: LayoutLayerID(name: "M1", purpose: "drawing"),
                    netID: netAID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: -0.5, y: -0.5),
                        size: LayoutSize(width: bridgeWidth, height: 1)
                    ))
                ),
                LayoutShape(
                    layer: LayoutLayerID(name: "M1", purpose: "drawing"),
                    netID: netBID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 19.5, y: -0.5),
                        size: LayoutSize(width: 11, height: 1)
                    ))
                ),
            ],
            instances: [
                LayoutInstance(id: r1InstanceID, cellID: resistor.id, name: "R1", transform: LayoutTransform(translation: LayoutPoint(x: 0, y: 0))),
                LayoutInstance(id: r2InstanceID, cellID: resistor.id, name: "R2", transform: LayoutTransform(translation: LayoutPoint(x: 10, y: 0))),
                LayoutInstance(id: c1InstanceID, cellID: capacitor.id, name: "C1", transform: LayoutTransform(translation: LayoutPoint(x: 20, y: 0))),
                LayoutInstance(id: c2InstanceID, cellID: capacitor.id, name: "C2", transform: LayoutTransform(translation: LayoutPoint(x: 30, y: 0))),
            ],
            nets: [
                LayoutNet(id: netAID, name: "net0"),
                LayoutNet(id: netBID, name: "net1"),
            ]
        )
        return LayoutDocument(name: "Layout", cells: [resistor, capacitor, top], topCellID: top.id)
    }

    private func makeHierarchicalLayout(
        r1InstanceID: UUID,
        r2InstanceID: UUID,
        netID: UUID,
        layoutNetName: String = "net0"
    ) -> LayoutDocument {
        let device = LayoutCell(name: "RES", pins: [
            LayoutPin(
                name: "pos",
                position: LayoutPoint(x: 0, y: 0),
                size: LayoutSize(width: 1, height: 1),
                layer: LayoutLayerID(name: "M1", purpose: "drawing")
            ),
        ])
        let wrapper = LayoutCell(
            name: "WRAP",
            shapes: [
                LayoutShape(
                    layer: LayoutLayerID(name: "M1", purpose: "drawing"),
                    netID: netID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: -0.5, y: -0.5),
                        size: LayoutSize(width: 11, height: 1)
                    ))
                ),
            ],
            instances: [
                LayoutInstance(id: r1InstanceID, cellID: device.id, name: "R1"),
                LayoutInstance(
                    id: r2InstanceID,
                    cellID: device.id,
                    name: "R2",
                    transform: LayoutTransform(translation: LayoutPoint(x: 10, y: 0))
                ),
            ],
            nets: [LayoutNet(id: netID, name: layoutNetName)]
        )
        let top = LayoutCell(
            name: "TOP",
            instances: [LayoutInstance(cellID: wrapper.id, name: "XWRAP")]
        )
        return LayoutDocument(name: "Layout", cells: [device, wrapper, top], topCellID: top.id)
    }

    private func makePolygonTerminalLayout(
        netID: UUID,
        firstTerminalProperties: [String: String] = ["lvs.component": "R1", "lvs.pin": "pos"]
    ) -> LayoutDocument {
        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let shapes = [
            LayoutShape(
                layer: m1,
                netID: netID,
                geometry: .rect(LayoutRect(
                    origin: LayoutPoint(x: -0.5, y: -0.5),
                    size: LayoutSize(width: 1, height: 1)
                )),
                properties: firstTerminalProperties
            ),
            LayoutShape(
                layer: m1,
                netID: netID,
                geometry: .rect(LayoutRect(
                    origin: LayoutPoint(x: 9.5, y: -0.5),
                    size: LayoutSize(width: 1, height: 1)
                )),
                properties: ["lvs.component": "R2", "lvs.pin": "pos"]
            ),
            LayoutShape(
                layer: m1,
                netID: netID,
                geometry: .rect(LayoutRect(
                    origin: LayoutPoint(x: -0.5, y: -0.5),
                    size: LayoutSize(width: 11, height: 1)
                ))
            ),
        ]
        let top = LayoutCell(
            name: "TOP",
            shapes: shapes,
            nets: [LayoutNet(id: netID, name: "net0")]
        )
        return LayoutDocument(name: "Layout", cells: [top], topCellID: top.id)
    }

    private func makePolygonDuplicateTerminalLayout(netID: UUID, duplicateNetID: UUID) -> LayoutDocument {
        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let top = LayoutCell(
            name: "TOP",
            shapes: [
                LayoutShape(
                    layer: m1,
                    netID: netID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: -0.5, y: -0.5),
                        size: LayoutSize(width: 11, height: 1)
                    ))
                ),
                LayoutShape(
                    layer: m1,
                    netID: netID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: -0.5, y: -0.5),
                        size: LayoutSize(width: 1, height: 1)
                    )),
                    properties: ["lvs.component": "R1", "lvs.pin": "pos"]
                ),
                LayoutShape(
                    layer: m1,
                    netID: netID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 9.5, y: -0.5),
                        size: LayoutSize(width: 1, height: 1)
                    )),
                    properties: ["lvs.component": "R2", "lvs.pin": "pos"]
                ),
                LayoutShape(
                    layer: m1,
                    netID: duplicateNetID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 50, y: 50),
                        size: LayoutSize(width: 1, height: 1)
                    )),
                    properties: ["lvs.component": "R1", "lvs.pin": "pos"]
                ),
            ],
            nets: [
                LayoutNet(id: netID, name: "net0"),
                LayoutNet(id: duplicateNetID, name: "duplicate"),
            ]
        )
        return LayoutDocument(name: "Layout", cells: [top], topCellID: top.id)
    }

    private func makeSingleTerminalLayout(
        r1InstanceID: UUID,
        netID: UUID,
        externalPinName: String?
    ) -> LayoutDocument {
        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let device = LayoutCell(name: "RES", pins: [
            LayoutPin(
                name: "pos",
                position: LayoutPoint(x: 0, y: 0),
                size: LayoutSize(width: 1, height: 1),
                layer: m1
            ),
        ])
        let pins = externalPinName.map { name in [
            LayoutPin(
                name: name,
                position: LayoutPoint(x: 0, y: 0),
                size: LayoutSize(width: 1, height: 1),
                layer: m1,
                netID: netID
            ),
        ] } ?? []
        let top = LayoutCell(
            name: "TOP",
            shapes: [
                LayoutShape(
                    layer: m1,
                    netID: netID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: -0.5, y: -0.5),
                        size: LayoutSize(width: 1, height: 1)
                    ))
                ),
            ],
            pins: pins,
            instances: [LayoutInstance(id: r1InstanceID, cellID: device.id, name: "R1")],
            nets: [LayoutNet(id: netID, name: "net0")]
        )
        return LayoutDocument(name: "Layout", cells: [device, top], topCellID: top.id)
    }

    private func makeRawMOSLayout(
        name: String,
        width: Double,
        length: Double,
        kind: RawMOSTestKind = .nmos,
        fingerCount: Int = 1,
        duplicate: Bool = false
    ) -> LayoutDocument {
        let active = LayoutLayerID(name: "ACTIVE", purpose: "drawing")
        let poly = LayoutLayerID(name: "POLY", purpose: "drawing")
        let implant = LayoutLayerID(name: kind.implantLayerName, purpose: "drawing")
        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let baseShapes = rawMOSShapes(
            origin: .zero,
            width: width,
            length: length,
            fingerCount: fingerCount,
            activeLayer: active,
            polyLayer: poly,
            implantLayer: implant,
            m1Layer: m1
        )
        let duplicateShapes = duplicate ? rawMOSShapes(
            origin: LayoutPoint(x: 20, y: 0),
            width: width,
            length: length,
            fingerCount: fingerCount,
            activeLayer: active,
            polyLayer: poly,
            implantLayer: implant,
            m1Layer: m1
        ) : []
        let labels = [
            LayoutLabel(
                text: name,
                position: LayoutPoint(x: 2, y: width / 2),
                layer: m1
            ),
        ] + (duplicate ? [
            LayoutLabel(
                text: name,
                position: LayoutPoint(x: 22, y: width / 2),
                layer: m1
            ),
        ] : [])
        let top = LayoutCell(
            name: "TOP",
            shapes: baseShapes + duplicateShapes,
            labels: labels
        )
        return LayoutDocument(name: "Layout", cells: [top], topCellID: top.id)
    }

    private func makeRawMOSConnectivityLayout(
        netID: UUID,
        connectDrains: Bool,
        useNumericImportedLayers: Bool = false
    ) -> LayoutDocument {
        let active = useNumericImportedLayers
            ? LayoutLayerID(name: "L20", purpose: "D0")
            : LayoutLayerID(name: "ACTIVE", purpose: "drawing")
        let poly = useNumericImportedLayers
            ? LayoutLayerID(name: "L30", purpose: "D0")
            : LayoutLayerID(name: "POLY", purpose: "drawing")
        let implant = useNumericImportedLayers
            ? LayoutLayerID(name: "L40", purpose: "D0")
            : LayoutLayerID(name: "NIMP", purpose: "drawing")
        let m1 = useNumericImportedLayers
            ? LayoutLayerID(name: "L1", purpose: "D0")
            : LayoutLayerID(name: "M1", purpose: "drawing")
        let width = 10.0
        let length = 1.0
        let leftOrigin = LayoutPoint(x: 0, y: 0)
        let rightOrigin = LayoutPoint(x: 10, y: 0)
        var shapes = rawMOSShapes(
            origin: leftOrigin,
            width: width,
            length: length,
            fingerCount: 1,
            activeLayer: active,
            polyLayer: poly,
            implantLayer: implant,
            m1Layer: m1,
            drainNetID: netID
        ) + rawMOSShapes(
            origin: rightOrigin,
            width: width,
            length: length,
            fingerCount: 1,
            activeLayer: active,
            polyLayer: poly,
            implantLayer: implant,
            m1Layer: m1,
            drainNetID: netID
        )
        if connectDrains {
            shapes.append(LayoutShape(
                layer: m1,
                netID: netID,
                geometry: .rect(LayoutRect(
                    origin: LayoutPoint(x: leftOrigin.x + 3.5, y: 0),
                    size: LayoutSize(width: rightOrigin.x, height: width)
                ))
            ))
        }
        let top = LayoutCell(
            name: "TOP",
            shapes: shapes,
            labels: [
                LayoutLabel(text: "MN1", position: LayoutPoint(x: leftOrigin.x + 2, y: width / 2), layer: m1),
                LayoutLabel(text: "MN2", position: LayoutPoint(x: rightOrigin.x + 2, y: width / 2), layer: m1),
            ],
            nets: [LayoutNet(id: netID, name: "net0")]
        )
        return LayoutDocument(name: "Layout", cells: [top], topCellID: top.id)
    }

    private func makeHierarchyCycleLayout() -> LayoutDocument {
        let topID = UUID()
        let childID = UUID()
        let top = LayoutCell(
            id: topID,
            name: "TOP",
            instances: [LayoutInstance(cellID: childID, name: "XCHILD")]
        )
        let child = LayoutCell(
            id: childID,
            name: "CHILD",
            instances: [LayoutInstance(cellID: topID, name: "XTOP")]
        )
        return LayoutDocument(name: "Layout", cells: [top, child], topCellID: topID)
    }

    private func makeImportedContactBridgeLayout(netID: UUID) -> LayoutDocument {
        let active = LayoutLayerID(name: "ACTIVE", purpose: "drawing")
        let contact = LayoutLayerID(name: "CONTACT", purpose: "cut")
        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let top = LayoutCell(
            name: "TOP",
            shapes: [
                LayoutShape(
                    layer: active,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: -0.5, y: -0.5),
                        size: LayoutSize(width: 1, height: 1)
                    )),
                    properties: ["lvs.component": "R1", "lvs.pin": "pos"]
                ),
                LayoutShape(
                    layer: contact,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: -0.1, y: -0.1),
                        size: LayoutSize(width: 0.2, height: 0.2)
                    ))
                ),
                LayoutShape(
                    layer: m1,
                    netID: netID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: -0.5, y: -0.5),
                        size: LayoutSize(width: 11, height: 1)
                    ))
                ),
                LayoutShape(
                    layer: m1,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 9.5, y: -0.5),
                        size: LayoutSize(width: 1, height: 1)
                    )),
                    properties: ["lvs.component": "R2", "lvs.pin": "pos"]
                ),
            ],
            nets: [LayoutNet(id: netID, name: "net0")]
        )
        return LayoutDocument(name: "Layout", cells: [top], topCellID: top.id)
    }

    private func makeSharedDiffusionSeriesMOSLayout(netID: UUID) -> LayoutDocument {
        let active = LayoutLayerID(name: "ACTIVE", purpose: "drawing")
        let poly = LayoutLayerID(name: "POLY", purpose: "drawing")
        let implant = LayoutLayerID(name: "NIMP", purpose: "drawing")
        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let width = 10.0
        let top = LayoutCell(
            name: "TOP",
            shapes: [
                LayoutShape(
                    layer: active,
                    geometry: .rect(LayoutRect(
                        origin: .zero,
                        size: LayoutSize(width: 6, height: width)
                    ))
                ),
                LayoutShape(
                    layer: implant,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: -0.2, y: -0.2),
                        size: LayoutSize(width: 6.4, height: width + 0.4)
                    ))
                ),
                LayoutShape(
                    layer: poly,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 1.5, y: -1),
                        size: LayoutSize(width: 1, height: width + 2)
                    ))
                ),
                LayoutShape(
                    layer: poly,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 3.5, y: -1),
                        size: LayoutSize(width: 1, height: width + 2)
                    ))
                ),
                LayoutShape(
                    layer: m1,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 0, y: 0),
                        size: LayoutSize(width: 0.5, height: width)
                    ))
                ),
                LayoutShape(
                    layer: m1,
                    netID: netID,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 2.5, y: 0),
                        size: LayoutSize(width: 0.5, height: width)
                    ))
                ),
                LayoutShape(
                    layer: m1,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 5.5, y: 0),
                        size: LayoutSize(width: 0.5, height: width)
                    ))
                ),
                LayoutShape(
                    layer: m1,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 1.5, y: width + 0.2),
                        size: LayoutSize(width: 3, height: 0.5)
                    ))
                ),
                LayoutShape(
                    layer: m1,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 0, y: -2),
                        size: LayoutSize(width: 6, height: 0.5)
                    ))
                ),
            ],
            labels: [
                LayoutLabel(text: "MN1", position: LayoutPoint(x: 2.0, y: width / 2), layer: m1),
                LayoutLabel(text: "MN2", position: LayoutPoint(x: 4.0, y: width / 2), layer: m1),
            ],
            nets: [LayoutNet(id: netID, name: "net0")]
        )
        return LayoutDocument(name: "Layout", cells: [top], topCellID: top.id)
    }

    private func makeRawResistorLayout(name: String, width: Double, length: Double) -> LayoutDocument {
        let poly = LayoutLayerID(name: "POLY", purpose: "drawing")
        let resi = LayoutLayerID(name: "RESI", purpose: "drawing")
        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let polyBox = LayoutRect(origin: .zero, size: LayoutSize(width: length, height: width))
        let top = LayoutCell(
            name: "TOP",
            shapes: [
                LayoutShape(layer: poly, geometry: .rect(polyBox)),
                LayoutShape(layer: resi, geometry: .rect(polyBox)),
                LayoutShape(
                    layer: m1,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 0, y: 0),
                        size: LayoutSize(width: 0.5, height: width)
                    ))
                ),
                LayoutShape(
                    layer: m1,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: length - 0.5, y: 0),
                        size: LayoutSize(width: 0.5, height: width)
                    ))
                ),
            ],
            labels: [LayoutLabel(text: name, position: polyBox.center, layer: m1)]
        )
        return LayoutDocument(name: "Layout", cells: [top], topCellID: top.id)
    }

    private func makeRawCapacitorLayout(
        name: String,
        overlapWidth: Double,
        overlapHeight: Double
    ) -> LayoutDocument {
        let active = LayoutLayerID(name: "ACTIVE", purpose: "drawing")
        let poly = LayoutLayerID(name: "POLY", purpose: "drawing")
        let nimp = LayoutLayerID(name: "NIMP", purpose: "drawing")
        let nwell = LayoutLayerID(name: "NWELL", purpose: "drawing")
        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let activeBox = LayoutRect(
            origin: .zero,
            size: LayoutSize(width: overlapWidth + 1, height: overlapHeight)
        )
        let polyBox = LayoutRect(
            origin: LayoutPoint(x: 1, y: 0),
            size: LayoutSize(width: overlapWidth + 1, height: overlapHeight)
        )
        let top = LayoutCell(
            name: "TOP",
            shapes: [
                LayoutShape(layer: active, geometry: .rect(activeBox)),
                LayoutShape(layer: nimp, geometry: .rect(activeBox.expanded(by: 0.2, 0.2))),
                LayoutShape(layer: nwell, geometry: .rect(activeBox.expanded(by: 0.3, 0.3))),
                LayoutShape(layer: poly, geometry: .rect(polyBox)),
                LayoutShape(
                    layer: m1,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 0, y: 0),
                        size: LayoutSize(width: 0.5, height: overlapHeight)
                    ))
                ),
                LayoutShape(
                    layer: m1,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: overlapWidth + 1.5, y: 0),
                        size: LayoutSize(width: 0.5, height: overlapHeight)
                    ))
                ),
            ],
            labels: [LayoutLabel(text: name, position: activeBox.center, layer: m1)]
        )
        return LayoutDocument(name: "Layout", cells: [top], topCellID: top.id)
    }

    private func makeImportedVoltageDividerLayout() -> LayoutDocument {
        let poly = LayoutLayerID(name: "POLY", purpose: "drawing")
        let resi = LayoutLayerID(name: "RESI", purpose: "drawing")
        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let r1Body = LayoutRect(origin: .zero, size: LayoutSize(width: 10, height: 2))
        let r2Body = LayoutRect(origin: LayoutPoint(x: 20, y: 0), size: LayoutSize(width: 10, height: 2))
        let resiEnclosure = 0.12
        let top = LayoutCell(
            name: "TOP",
            shapes: [
                LayoutShape(layer: poly, geometry: .rect(r1Body)),
                LayoutShape(layer: resi, geometry: .rect(r1Body.expanded(by: resiEnclosure, resiEnclosure))),
                LayoutShape(layer: poly, geometry: .rect(r2Body)),
                LayoutShape(layer: resi, geometry: .rect(r2Body.expanded(by: resiEnclosure, resiEnclosure))),
                LayoutShape(
                    layer: m1,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 0, y: 0),
                        size: LayoutSize(width: 0.5, height: 2)
                    ))
                ),
                LayoutShape(
                    layer: m1,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 9.5, y: 0),
                        size: LayoutSize(width: 11, height: 2)
                    ))
                ),
                LayoutShape(
                    layer: m1,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: 29.5, y: 0),
                        size: LayoutSize(width: 0.5, height: 2)
                    ))
                ),
            ],
            labels: [
                LayoutLabel(text: "R1", position: r1Body.center, layer: m1),
                LayoutLabel(text: "R2", position: r2Body.center, layer: m1),
                LayoutLabel(text: "vin", position: LayoutPoint(x: 0.25, y: 1), layer: m1),
                LayoutLabel(text: "out", position: LayoutPoint(x: 15, y: 1), layer: m1),
                LayoutLabel(text: "0", position: LayoutPoint(x: 29.75, y: 1), layer: m1),
            ]
        )
        return LayoutDocument(name: "ImportedVoltageDivider", cells: [top], topCellID: top.id)
    }

    private enum RawMOSTestKind {
        case nmos
        case pmos

        var implantLayerName: String {
            switch self {
            case .nmos: return "NIMP"
            case .pmos: return "PIMP"
            }
        }
    }

    private func rawMOSShapes(
        origin: LayoutPoint,
        width: Double,
        length: Double,
        fingerCount: Int,
        activeLayer: LayoutLayerID,
        polyLayer: LayoutLayerID,
        implantLayer: LayoutLayerID,
        m1Layer: LayoutLayerID,
        drainNetID: UUID? = nil
    ) -> [LayoutShape] {
        let activeWidth = Double(fingerCount + 1) * 2
        let activeShape = LayoutShape(
            layer: activeLayer,
            geometry: .rect(LayoutRect(
                origin: origin,
                size: LayoutSize(width: activeWidth, height: width)
            ))
        )
        let implantShape = LayoutShape(
            layer: implantLayer,
            geometry: .rect(LayoutRect(
                origin: LayoutPoint(x: origin.x - 0.2, y: origin.y - 0.2),
                size: LayoutSize(width: activeWidth + 0.4, height: width + 0.4)
            ))
        )
        let polyShapes = (0..<fingerCount).map { index in
            LayoutShape(
                layer: polyLayer,
                geometry: .rect(LayoutRect(
                    origin: LayoutPoint(x: origin.x + 1.5 + Double(index) * 2, y: origin.y - 1),
                    size: LayoutSize(width: length, height: width + 2)
                ))
            )
        }
        let terminalShapes = [
            LayoutShape(
                layer: m1Layer,
                geometry: .rect(LayoutRect(
                    origin: LayoutPoint(x: origin.x, y: origin.y),
                    size: LayoutSize(width: 0.5, height: width)
                ))
            ),
            LayoutShape(
                layer: m1Layer,
                netID: drainNetID,
                geometry: .rect(LayoutRect(
                    origin: LayoutPoint(x: origin.x + activeWidth - 0.5, y: origin.y),
                    size: LayoutSize(width: 0.5, height: width)
                ))
            ),
            LayoutShape(
                layer: m1Layer,
                geometry: .rect(LayoutRect(
                    origin: LayoutPoint(x: origin.x + 1.5, y: origin.y + width + 0.2),
                    size: LayoutSize(width: activeWidth - 2.5, height: 0.5)
                ))
            ),
            LayoutShape(
                layer: m1Layer,
                geometry: .rect(LayoutRect(
                    origin: LayoutPoint(x: origin.x, y: origin.y - 2),
                    size: LayoutSize(width: activeWidth, height: 0.5)
                ))
            ),
        ]
        return [activeShape, implantShape] + polyShapes + terminalShapes
    }
}
