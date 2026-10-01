# Circuit Studio Cockpit

## Purpose and Scope

Parent: [LSI](../DESIGN.md). This package provides human design interaction and
review over canonical domain state and the host run ledger. UI breadth is not a
claim that native domain algorithms or production closure are implemented.

## Responsibilities and Boundaries

The cockpit displays domain results, diffs, diagnostics and waveform/layout
projections, and submits explicit human decisions. It owns presentation state,
not canonical design storage, extraction, simulation, trust or release decisions.

## Related Designs

| Design | Relationship | Contract used | Caution |
|---|---|---|---|
| [LSI](../DESIGN.md) | parent | Human intervention in the native flow | Presentation is not signoff evidence |
| [Xcircuite](../Xcircuite/DESIGN.md) | depends on | Exact state, artifacts and run ledger | Preserve reviewed identity through resume |
| [DesignFlowKernel](../DesignFlowKernel/DESIGN.md) | depends on | Approval/rejection/resume | Bind decisions to the exact reviewed result |
| [ReleaseEngine](../ReleaseEngine/DESIGN.md) | coordinates with | Release eligibility and authorization | UI cannot issue trust on behalf of the owner |

## Architecture

```text
Canonical revision + domain results + ledger -> UI projections
    -> explicit human decision -> canonical approval/resume contract
```

## Contracts and Invariants

Human review must identify the candidate, process profile, diff, diagnostics and
raw evidence actually used by the run. A decision against another revision or
bundle cannot authorize the current candidate. A displayed success must retain
its actual domain scope and qualification status.

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
