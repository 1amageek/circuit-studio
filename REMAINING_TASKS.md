# circuit-studio Remaining Tasks

Updated: 2026-07-26

circuit-studio is the human control plane. It must consume the same canonical
ledger, action-domain, artifacts, trust decisions, approvals, and resume
contracts as headless Xcircuite rather than owning parallel domain truth.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
| CST-4 | P2 | circuit-studio | Add stable visual and accessibility regression coverage for the review cockpit. | Representative clean, failed, blocked, partial, tampered, approval-required, and resumed runs have deterministic view-state assertions plus keyboard, VoiceOver-label, and large-data rendering checks. |

## Completed tasks

| ID | Completed | Evidence |
|---|---|---|
| CST-3 | 2026-07-26 | `RealSignoffPEXEndToEndTests` now runs Magic DRC, Netgen LVS, Magic PEX, and a CoreSpice/ngspice comparison against retained Sky130 inputs, persists the engine-owned summaries, raw tool logs, exact executable/PDK profile, design diff, and simulation evidence into one canonical run, verifies every artifact before review, projects DRC/LVS/PEX/simulation cards, records human approval and an explicit resume decision, resumes the same immutable plan, and reloads the succeeded shared ledger. The dedicated real-tool workflow writes a required marker and exact tool environment so missing tools fail instead of producing a skipped pass. |
| CST-1 | 2026-07-26 | `RunReviewActionDomainCatalog` indexes the exact retained planning action-domain snapshot when present and otherwise builds the same canonical snapshot used by Xcircuite. DRC, LVS, PEX, simulation, and post-layout repair hints now obtain operation presence, maturity, inputs, and gates from that catalog. Integrity, schema, and run-identity mismatches fail explicitly. `RunReviewSignoffProjectionTests` verifies both canonical and retained-snapshot paths. |
| CST-2 | 2026-07-26 | Ready cockpit actions now use `RunReviewService.runSuggestedAction`, which records at most one successful selection and delegates resolution plus execution to Xcircuite's typed semantic dispatcher. The UI exposes run progress and typed failure messages without copying operation switches. Xcircuite tests cover all semantic operation projections and distinct next/suggested action IDs; circuit-studio planning tests execute post-execution verification, retain its action/artifact path, reject missing selections with the typed Xcircuite error, and prove retry does not duplicate the selection record. |

## Responsibility boundary

UI state and presentation belong here. Canonical design state, domain
algorithms, artifact schemas, trust evaluation, flow lifecycle, and release
authorization stay in their owning libraries.

## Evidence reviewed

- `README.md`
- `Package.swift`
- `Sources/CircuitStudioApp/Services/RunReviewService+Signoff.swift`
- `Sources/CircuitStudioApp/Services/RunReviewService.swift`
- Shared ledger, suggested-action, approval, resume, and artifact-rendering paths
- Real-tool GitHub workflow
- `Sources` incomplete-implementation marker scan
