# ProjectConfiguration

## Purpose and Scope

Own project PEX configuration persistence in the existing filesystem platform
adapter [ProjectService](../Services/ProjectService.swift). Parent:
[CircuitStudioApp](../DESIGN.md). No children.

## Responsibilities and Boundaries

Save/load the complete typed PEXProjectConfig as executable JSON. Native
reference decoding, budgets and backend admission belong to PEXRuntime. The
reference document's decoded configuration/calibration URLs remain unchanged.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CircuitStudioApp](../DESIGN.md) | parent | Filesystem adapter composition | Project persistence | Keep project-view and document bases explicit |
| [CircuitStudioCore](../../CircuitStudioCore/DESIGN.md) | used by | PEXExtractionService | Runtime projection | Preserve actual failures |
| [PEXRuntime](../../../../PEXEngine/Sources/PEXRuntime/DESIGN.md) | depends on | PEXProjectConfig mapping and native loader | Bounded native admission | No Studio native decoder |

## Architecture

```text
typed config -> .xcircuite/pex.json -> load / top-cell update / ensure-files
                                 -> public ExtractCommand.run()
```

## Contracts and Invariants

Schema version remains 1. App-facing config paths are project-root-relative;
persisted JSON paths are relative to the actual document directory.
PEXProjectPathProjection is the single owner of this explicit projection. Absolute
paths and non-path metadata remain unchanged. It transforms layout, netlist,
technology, corner technologies, native reference document, workspace, executable,
PDK root and all declared profile deck/view paths. Save projects the project view
to .xcircuite/pex.json; load projects back for GUI file writers. Resolving the
project-view and persisted paths yields the same file target. Blank native input
remains blank for lower typed refusal. This is the single executable CLI/Studio
configuration; an unconsumed TOML generator and its path API are removed.

JSON save, top-cell update and ensure-files preserve native selection and unrelated
typed fields. Core extraction always maps the actual configURL. The obsolete
projectDirectory base override is removed from both request types and direct
callers; no second implicit runtime base remains. The decoded native reference's
configuration/calibration URLs are not projected or rewritten.

## State, Ownership, and Lifecycle

ProjectService owns atomic persisted config writes. Engine runs own immutable
captured bytes and manifests. Tests own separate UUID workspaces; CLI and Studio
runs use disjoint output roots and retain original inputs throughout each run.

## Failure, Concurrency, and Constraints

Native missing/blank or wrong-backend input is rejected by the public lower
contract. Studio must preserve typed admission failure. A backend-completed failed
run retains its full result through the Core executionFailed error.

## Verification and Change Impact

StudioNativePEXConfigurationTests proves JSON preservation across save, top-cell
update and ensure-files, canonical JSON selection through the actual public CLI,
and actual default-engine command results. The analytical sheet coefficient
definition is a test input, not fitted library or foundry evidence. Changes to
path projection require rechecking both actual config document locations.
