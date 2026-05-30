import Foundation

/// Turns a signoff review into STRUCTURED, actionable findings — the "Explain" stage
/// of the design loop (AGENTS.md §5). DRC/LVS diagnostics are otherwise free strings
/// and booleans; an agent (or human) deciding the next edit needs `{stage, reason,
/// component, suggestedActions}`, which is what this produces.
///
/// It does not invent facts: every finding traces to a diagnostic the tools emitted;
/// `reason`/`suggestedActions` are a fixed classification of the rule, not a guess
/// about the layout.
public struct SignoffEvaluationService: Sendable {

    public struct Finding: Sendable, Hashable, Codable {
        public let stage: String            // "drc" | "lvs"
        public let severity: String         // "error" | "warning" | "info"
        public let reason: String           // classified failure mode
        public let ruleID: String?
        public let component: String?
        public let net: String?
        public let message: String
        public let suggestedActions: [String]

        public init(
            stage: String, severity: String, reason: String, ruleID: String?,
            component: String?, net: String?, message: String, suggestedActions: [String]
        ) {
            self.stage = stage
            self.severity = severity
            self.reason = reason
            self.ruleID = ruleID
            self.component = component
            self.net = net
            self.message = message
            self.suggestedActions = suggestedActions
        }
    }

    public struct Evaluation: Sendable, Hashable, Codable {
        public let passed: Bool
        public let findings: [Finding]
        /// Findings that gate the design (error severity).
        public var blockingFindings: [Finding] { findings.filter { $0.severity == "error" } }

        public init(passed: Bool, findings: [Finding]) {
            self.passed = passed
            self.findings = findings
        }
    }

    public init() {}

    /// Structures every diagnostic in `review` into an actionable finding.
    public func evaluate(_ review: ExternalSignoffReview) -> Evaluation {
        let findings = review.reports.flatMap { report in
            report.diagnostics.map { diagnostic in
                finding(stage: report.kind, diagnostic: diagnostic)
            }
        }
        return Evaluation(passed: review.passed, findings: findings)
    }

    private func finding(
        stage: ExternalSignoffToolReport.Kind,
        diagnostic: ExternalSignoffDiagnostic
    ) -> Finding {
        let (reason, actions) = classify(stage: stage, diagnostic: diagnostic)
        return Finding(
            stage: stage.rawValue,
            severity: diagnostic.severity.rawValue,
            reason: reason,
            ruleID: diagnostic.ruleID,
            component: diagnostic.componentName,
            net: diagnostic.netName,
            message: diagnostic.message,
            suggestedActions: actions
        )
    }

    /// Maps a tool rule to a failure mode and concrete next actions. The rule code is
    /// the source of truth; the actions are how an agent or human moves the design.
    private func classify(
        stage: ExternalSignoffToolReport.Kind,
        diagnostic: ExternalSignoffDiagnostic
    ) -> (reason: String, actions: [String]) {
        let rule = (diagnostic.ruleID ?? "").lowercased()
        switch stage {
        case .lvs:
            if rule.contains("mismatch") {
                return ("layout_schematic_mismatch", [
                    "compare_device_counts_layout_vs_schematic",
                    "check_net_connectivity_at_reported_nets",
                    "verify_port_and_label_mapping",
                ])
            }
            if rule == "driver" {
                return ("lvs_tool_error", ["inspect_lvs_driver_log", "verify_inputs_exist"])
            }
            return ("lvs_violation", ["inspect_lvs_report"])
        case .drc:
            if rule == "driver" {
                return ("drc_tool_error", ["inspect_drc_driver_log", "verify_cell_loaded"])
            }
            // Sky130/Magic rule codes encode the dimension class in the suffix
            // (e.g. met1.2 = metal1 spacing, *.1 = width, *.3 = enclosure/extension).
            if rule.hasSuffix(".2") {
                return ("min_spacing_violation", [
                    "increase_spacing_between_shapes_on_\(layer(of: rule))",
                    "reroute_to_widen_the_channel",
                ])
            }
            if rule.hasSuffix(".1") {
                return ("min_width_violation", ["widen_shape_on_\(layer(of: rule))"])
            }
            if rule.hasSuffix(".3") || rule.hasSuffix(".4") {
                return ("enclosure_or_extension_violation", [
                    "extend_enclosing_layer_around_\(layer(of: rule))",
                ])
            }
            return ("drc_violation", ["inspect_rule_\(diagnostic.ruleID ?? "unknown")"])
        }
    }

    /// The layer prefix of a rule code (e.g. "met1" from "met1.2").
    private func layer(of rule: String) -> String {
        if let dot = rule.firstIndex(of: ".") {
            return String(rule[rule.startIndex..<dot])
        }
        return rule.isEmpty ? "unknown" : rule
    }
}
