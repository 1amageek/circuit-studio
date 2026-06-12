# circuit-studio

Human control plane of the design harness: a macOS app for schematic capture,
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
| Review (⌃⌘4) | Run review cockpit: reads `.xcircuite/runs`, shows stage results and gates, records approve/reject decisions (`XcircuiteApprovalRecord`); re-running the same runID resumes past the gate |

## Key services

| Service | Responsibility |
|---|---|
| `LiveSignoffService` | Real DRC/LVS/PEX wired into the studio flow |
| `XcircuiteEvidenceRunRecorder` | Mirrors evidence bundles into the run ledger (digest-verified artifact copies) |
| `RunReviewService` | Reads the run ledger, writes approval decisions — no cockpit-private copies |
| `GoalDrivenLayoutAgent` | Closes `.subckt` intents through goal commands only, gated on trust report + replay determinism + GDS-reimport LVS |
| `HeadlessRoundTripService` | subckt → place → route → DRC/LVS → GDS round trip, used as an end-to-end regression |

## Build & test

```bash
swift build
swift test   # tool-gated suites (Magic/Netgen/ngspice) skip when tools are absent
```
