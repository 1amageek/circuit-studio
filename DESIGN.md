# Circuit Studio Cockpit

## Purpose and Scope

Parent: [LSI](../DESIGN.md). This package provides human design interaction and
review over canonical domain state and the host run ledger. UI breadth is not a
claim that native domain algorithms or production closure are implemented.

## Responsibilities and Boundaries

The cockpit displays domain results, diffs, diagnostics and waveform/layout
projections, and submits explicit human decisions. It owns presentation state,
not canonical design storage, extraction, simulation, trust or release decisions.

GoalDrivenLayoutAgent open-net diagnostics preserve the connectivity owner's scoped
NetReference (occurrence index plus local net UUID). A root-cell name is attached
only to the exact reference returned by ConnectivityAnalysis.rootNetReference;
child or unresolved references retain their scoped identity without a root-name
alias. The wiringIncomplete error and open count remain unchanged. The focused
GoalDrivenLayoutAgentTests.scopedOpenDiagnostics test covers identical UUIDs in
root and child occurrences without exercising routing or closure qualification.

## Related Designs

| Design | Relationship | Contract used | Caution |
|---|---|---|---|
| [LSI](../DESIGN.md) | parent | Human intervention in the native flow | Presentation is not signoff evidence |
| [Xcircuite](../Xcircuite/DESIGN.md) | depends on | Exact state, artifacts and run ledger | Preserve reviewed identity through resume |
| [DesignFlowKernel](../DesignFlowKernel/DESIGN.md) | depends on | Approval/rejection/resume | Bind decisions to the exact reviewed result |
| [ReleaseEngine](../ReleaseEngine/DESIGN.md) | coordinates with | Release eligibility and authorization | UI cannot issue trust on behalf of the owner |

[CircuitStudioCore](Sources/CircuitStudioCore/DESIGN.md) owns the typed simulation
projection, including explicit caller policy and retained native transient limits.

## Architecture

```text
Canonical revision + domain results + ledger -> UI projections
    -> explicit human decision -> canonical approval/resume contract
```

## Contracts and Invariants

Human review must identify the candidate, process profile, diff, diagnostics and
raw evidence actually used by the run. A decision against another revision or
bundle cannot authorize the current candidate. A displayed success must retain
its actual domain scope and qualification status. The simulation recorder's schema-2
summary retains each completed native transient result's exact execution policy
source and seven ceilings from SimulationResult; it does not reconstruct policy
from application defaults or from partial source options.

## State, Ownership, and Lifecycle

Editor selection and display state are UI-owned. Domain changes are typed
operations against canonical state. Run progress, approvals and resumed work are
host-ledger projections; a view's lifetime does not own the canonical run.

## Verification and Change Impact

Verify affected UI actions through the same domain/ledger contracts as the CLI,
then exercise exact human review and resume in the cumulative system path.
Accessibility and large-run review remain measured UI obligations. Changes to
domain diagnostics, artifacts or approval identity require corresponding cockpit
projection checks.

[CircuitPhysicalDesign](Sources/CircuitPhysicalDesign/DESIGN.md) owns explicit
native device-context composition for synthesis, repair and pre-PEX verification.
