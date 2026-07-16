# circuit-studio

Human control plane of the design platform: a macOS app for schematic capture,
simulation, layout, physical verification, and run review. It operates on the same
`.xcircuite` project ledger, the same engines, and the same flow kernel as the
headless agent path — the cockpit reviews exactly the artifacts that agents and CI
produce.

## Targets

| Target | Responsibility |
|---|---|
| `CircuitStudioCore` | Shared app-domain logic |
| `SchematicEditor` | Schematic capture UI |
| `WaveformViewer` | Simulation waveform display |
| `CircuitStudioApp` | The app: editor workspaces, services (signoff, evidence recording, run review, goal-driven layout agent) |
| `circuit-studio-flow-runner` | Headless flow execution executable |
| `signoff` | Headless signoff executable |

## Workspaces

| Workspace | Purpose |
|---|---|
| Schematic | Capture, netlist, ERC |
| Simulation | OP/TRAN runs, waveforms, measurements |
| Layout | Layout editing with live DRC/connectivity/constraint verdicts |
| Review (⌃⌘4) | Run review cockpit: consumes `FlowRunReviewBundle` from `.xcircuite/runs`, shows review items, stage results, gates, artifact IDs, artifact paths, byte counts, artifact integrity status, next actions, suggested commands, a Plan Review section for candidate-plan artifacts, candidate steps, plan-verification artifacts, verification gates, risk reviews, risk approval/rejection actions, typed design diff summaries with domain/operation buckets, domain-aware path context, canvas-level visual summary, native viewport preview, native-coordinate canvas rendering with primitive labels, geometry-aware frame previews, visual focus, before/after previews, field-level side-by-side value changes, artifact refs, planning correctness gates, and selected commands, Verification Results cards for DRC/LVS/PEX summaries, simulation metrics/measurements, and post-layout comparison artifacts, plus Waiver Reviews for DRC/LVS waived evidence, unused waiver evidence, source-file lineage, edit proposals, post-edit verification records with structured DRC/LVS/ready-for-PEX drilldowns, and post-edit planning feedback status; resolves post-edit verification context from design-spec, layout-document / drc-layout, and optional design-unit artifacts; records suggested-command selections, waiver review decisions, waiver edit proposal selections, bounded waiver source-file edit applications, `Apply + Verify` / `Verify` post-edit verification actions, API/CLI apply-and-verify waiver edit actions, generated `planning/waiver-edit-feedback/<proposal-id>/candidate-plan.json` / `plan-verification.json`, failed post-edit feedback in `planning/rejected-plans.jsonl`, and other review actions in `actions.jsonl`, writes planning risk approvals to shared `FlowApprovalRecord` files, and records approve/reject decisions (`FlowApprovalRecord`); re-running the same runID resumes past the gate |

## Key services

| Service | Responsibility |
|---|---|
| `SignoffPDKContext` | Loads profile artifacts and resolves app signoff PDK roots / required files through `SignoffToolSupport` instead of process-specific Swift locators |
| `LayoutTechnologyResource` | Loads app-side `LayoutTechDatabase` resources from JSON so process layer/rule/via data is not owned by Swift constants |
| `LayoutTechnologyTranslationProfile` | Loads app-side layout translation policy from JSON so source/target layer names, via maps, and enclosure values are not owned by Swift constants |
| `LayoutTechnologyTranslator` | Translates generic-tech layout documents through an explicitly selected translation profile and target `LayoutTechDatabase` resource |
| `LayoutTechnologyCatalog` | Loads selectable layout technology inventory from JSON so default technology/routing profile selection is catalog-driven rather than process-named Swift facade driven |
| `MagicLayoutDRCChecker` | Runs Magic DRC through injected or catalog-selected `LayoutTechDatabase` data so layout checking is not tied to a process-named Swift checker |
| `LayoutRoutingProfile` | Loads app-side global/inter-block routing layer selection and routing geometry from JSON so router layer IDs and pad/track dimensions are not owned by Swift constants |
| `StandardCellLayoutProfile` | Loads app-side standard-cell layout policy, dynamic synthesizer geometry/routing policy, and fixed-cell catalogs from JSON so generator layer IDs, device models, DRC-derived dimensions, routing track policy, and reusable NAND/NOR geometry are not owned by Swift constants |
| `CMOSGateLibrary` | Builds standard CMOS gate netlists from explicit profile-derived device sizing so logic/topology APIs do not own process-specific transistor dimensions |
| `Level1DeviceModelProfile` | Loads timing-characterization MOS model cards, supply voltage, oxide capacitance, and technology provenance from JSON so catalog-backed default model selection, `circuit-studio-flow-runner --build-timing-library`, model-profile selection artifacts, and timing artifacts do not own process-specific model constants |
| `TimingModelProfileCatalog` | Loads and inspects selectable timing model profile inventory from JSON so Agent/CLI callers can preflight and select bundled or external profiles by ID or corner without process-specific Swift selectors |
| `SignoffRuleClassificationProfile` | Loads DRC rule-to-reason/action mappings from JSON so `SignoffEvaluationService` does not own process-specific rule IDs |
| `StandardCellLayoutProfileCatalog` | Loads selectable standard-cell layout profile inventory from JSON so default cell generation is catalog/profile selected rather than process-named Swift facade selected |
| `ProfiledStandardCellGenerator` | Generates fixed catalog cells from `StandardCellLayoutProfile` entries through a process-neutral API |
| `StandardCellSynthesizer` | Dynamic CMOS cell synthesizer that keeps topology-to-geometry behavior in Swift while loading layer, model, geometry, and output-routing policy from the standard-cell layout profile |
| `StandardCircuitSynthesizer` / `ProfiledAntennaTieGenerator` | Circuit-level placement, routing, and antenna-tie surfaces that load routing tracks, spacing-layer policy, tie geometry, and device models from the standard-cell layout profile and target LayoutTech resource |
| `LiveSignoffService` | Real DRC/LVS/PEX wired into the studio flow |
| `XcircuiteEvidenceRunRecorder` | Mirrors evidence bundles into the run ledger as canonical `CircuiteFoundation.ArtifactReference` values with digest-verified immutable copies; it does not maintain an app-specific artifact reference layer |
| `RunReviewService` | Reads `FlowRunReviewBundle` from the shared run ledger, including integrity-checked `stage-summary` artifacts, typed `XcircuiteCandidatePlan`, typed `XcircuitePlanVerification`, candidate steps, verification gates, risk reviews refreshed from current approval records, DRC/LVS/PEX summaries, simulation metric/measurement summaries, post-layout comparison summaries, DRC/LVS waiver review summaries, waiver source-file lineage, waiver edit proposals, waiver edit verification records, typed waiver edit verification report summaries, typed design diff summaries with domain-aware path context, canvas-level visual summary, native viewport summary, native-coordinate rendering summary with primitive labels and selection frames, geometry-aware frame summaries, visual focus, and field-level value changes, waiver edit planning feedback metadata, `design-diff.json`, planning correctness review items, next actions, suggested commands, and typed suggested-command selections, resolves `RunReviewWaiverEditVerificationContext` for post-edit verification inputs, writes planning risk approval/rejection records, waiver review decision records, waiver edit proposal selection/application/verification action records, apply-and-verify waiver edit action pairs through `DesignFlowCommand.applyWaiverEditProposalAndRunPostVerification`, post-edit waiver planning feedback artifacts, suggested-command selection action records, and approval decisions — no cockpit-private copies |
| `GoalDrivenLayoutAgent` | Closes `.subckt` intents through goal commands only, gated on trust report + replay determinism + GDS-reimport LVS |
| `HeadlessRoundTripService` | subckt → place → route → DRC/LVS → GDS round trip, used as an end-to-end regression |

## Build & test

```bash
perl -e 'alarm shift; exec @ARGV' 120 \
  xcodebuild -workspace Xcircuite.xcworkspace -scheme CircuitStudioApp \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO

perl -e 'alarm shift; exec @ARGV' 120 \
  xcodebuild test -workspace Xcircuite.xcworkspace -scheme CircuitStudioApp \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Tool-gated suites for Magic, Netgen, and ngspice report an explicit skip when
the corresponding executable is unavailable. Verification commands always use
a bounded timeout and produce an Xcode result bundle in workspace verification.
