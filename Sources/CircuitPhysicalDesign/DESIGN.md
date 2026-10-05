# Circuit Physical Design

## Purpose and Scope
Own circuit-to-layout synthesis, ownership evaluation and physical verification.
Parent: [Circuit Studio](../../DESIGN.md). Child:
[DeviceElectricalVerification](DeviceElectricalVerification/DESIGN.md).

## Responsibilities and Boundaries
Compose existing placement/routing/device generation with Layout native DRC and
independent extraction-based LVS. Domain geometry and numerical device models
remain lower-library responsibilities.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Circuit Studio](../../DESIGN.md) | parent | Auditable human flow | Typed commands | UI success is not signoff |
| [DeviceElectricalVerification](DeviceElectricalVerification/DESIGN.md) | child | Explicit device context | DRC consumer composition | Keep all callsites consistent |

## Architecture
```text
Schematic -> generated cells -> placement/routing/repair -> native DRC + LVS
 -> immutable verification report -> pre-PEX gate
```

## Contracts and Invariants
Synthesis repair and pre-PEX verification use the same explicit device context.
Physical reports retain native source occurrence, material roles and diagnostics;
failed preparation remains a failed gate. Raw source geometry is preserved.

## Verification and Change Impact
CircuitPhysicalDesignTests own topology/verification. DesignFlowServiceTests own
actual command pre-PEX gating and persisted report interpretation. Lower device
context changes require both boundaries to be rechecked.
