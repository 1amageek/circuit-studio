# Device Electrical Verification

## Purpose and Scope
Select the explicit native device-topology context for generated circuit layouts.
Parent: [CircuitPhysicalDesign](../DESIGN.md). No children.

## Responsibilities and Boundaries
The resistor generator owns poly and body-marker material roles. This adapter
passes those actual typed identities to the Device-owned preparation contract;
it never infers a device from cell names, labels or net IDs. Synthesis repair,
final synthesis DRC and pre-PEX physical verification share the same selection.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CircuitPhysicalDesign](../DESIGN.md) | parent | Circuit layout composition | Explicit profile selection | Gate failures are retained |
| [PassiveDevicePreparation](../../../../semiconductor-layout/Sources/LayoutVerify/PassiveDevicePreparation/DESIGN.md) | depends on | Exact body boundary and role provenance | Native topology | No numerical R qualification |

## Architecture
```text
Actual generator material roles + technology -> explicit native context
 -> repair / synthesis DRC / physical verification -> retained native DRC report
```

## Contracts and Invariants
When both resistor material roles are registered, choose the combined MOS/poly-
resistor context with those exact layer IDs. Without those materials the existing
MOS preparation handles the admitted technology; no marker semantics are guessed.
An unsupported body or failed native preparation cannot pass physical verification.
Reports retain the native context, raw hierarchy, scoped violations and diagnostics.
Existing extraction-based LVS owns open-net judgment; no short is suppressed.

## Verification and Change Impact
DesignFlowServiceTests retain all three original pre-PEX success requirements.
DeviceElectricalVerificationTests additionally reject unsupported bodies and
retain a real metal bypass short, source-scoped provenance and diagnostic failure.
Changes to generator roles or lower preparation require this actual consumer path
and synthesis repair to be rechecked.
