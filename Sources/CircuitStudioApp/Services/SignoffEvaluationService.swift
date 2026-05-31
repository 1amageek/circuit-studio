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

    /// DRC rule codes whose meaning we have verified, mapped to a failure mode and
    /// concrete next actions. Only these are classified confidently; the numeric
    /// suffix is NOT a reliable dimension-class encoding across all Sky130 rules, so
    /// an unknown code is reported generically rather than guessed (a wrong `reason`
    /// would be an unverified claim presented as fact).
    private static let knownDRCRules: [String: (reason: String, actions: [String])] = [
        "met1.1": ("min_width_violation", ["widen_met1_shape"]),
        "met1.2": ("min_spacing_violation", ["increase_spacing_between_met1_shapes", "reroute_to_widen_the_channel"]),
        "met2.1": ("min_width_violation", ["widen_met2_shape"]),
        "met2.2": ("min_spacing_violation", ["increase_spacing_between_met2_shapes", "reroute_to_widen_the_channel"]),
        "poly.1": ("min_width_violation", ["widen_poly_shape"]),
        "poly.2": ("min_spacing_violation", ["increase_spacing_between_poly_shapes"]),
        "li1.1": ("min_width_violation", ["widen_li1_shape"]),
        "li1.2": ("min_spacing_violation", ["increase_spacing_between_li1_shapes"]),
        "difftap.2": ("min_spacing_violation", ["increase_spacing_between_diffusion_shapes"]),
    ]

    /// Maps a tool rule to a failure mode and concrete next actions. The rule code is
    /// the source of truth; the actions are how an agent or human moves the design.
    /// Unknown DRC codes are reported as a generic violation (with the code) rather
    /// than classified by a heuristic that could mislabel them.
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
            if let known = Self.knownDRCRules[rule] {
                return known
            }
            return ("drc_violation", ["inspect_rule_\(diagnostic.ruleID ?? "unknown")_in_the_pdk_drc_manual"])
        case .antenna:
            if rule == "driver" {
                return ("antenna_tool_error", ["inspect_antenna_driver_log", "verify_cell_loaded"])
            }
            return ("antenna_violation", [
                "insert_antenna_diode_on_the_reported_gate_net",
                "jog_the_long_metal_to_a_higher_layer_then_back_down",
                "split_the_metal_run_so_no_single_layer_exceeds_the_ratio",
            ])
        case .density:
            if rule == "driver" {
                return ("density_tool_error", ["inspect_density_driver_log", "verify_cell_loaded"])
            }
            return ("density_violation", [
                "insert_metal_fill_to_raise_local_density_into_the_window",
                "remove_fill_or_widen_routing_to_lower_density_below_the_ceiling",
            ])
        }
    }
}
