# CircuitStudio Design Spec

This document defines the structured design input consumed by `DesignFlowDesignSpec` and the `circuit-studio-flow-runner --design-spec` command.

The design spec is a small, versioned JSON contract for Agent and CLI callers. It is not intended to replace standard signoff formats. It is an operation input that builds a schematic, generates SPICE, runs simulation, creates layout, gates DRC/LVS, injects PEX, compares post-layout results, and captures the source spec into the run manifest.

```mermaid
flowchart LR
  Spec["design-spec.json"] --> Build["SchematicDocument"]
  Build --> Netlist["SPICE netlist"]
  Build --> Layout["Auto layout"]
  Netlist --> Sim["Pre-layout simulation"]
  Layout --> Signoff["DRC / LVS gate"]
  Signoff --> PEX["PEX injection"]
  PEX --> Post["Post-layout simulation"]
  Post --> Manifest["round-trip-manifest.json"]
  Spec --> Capture["input-artifacts/design/"]
  Capture --> Manifest
```

## Compatibility

| Field | Required | Meaning |
|---|---:|---|
| `schemaVersion` | No | Version of this JSON contract. Missing means `1`. Only `1` is currently supported. |
| `name` | Yes | Stable design name. Used for default run directory names. |
| `title` | No | Human-readable title. Defaults to `name`. |
| `components` | Yes | Component instances to place in the schematic. |
| `nets` | Yes | Named electrical nets and their terminal ownership. |
| `analyses` | Yes | Pre-layout analysis commands. |
| `postLayoutAnalysis` | No | Post-layout analysis command. Defaults to the first `analyses` entry. |
| `pexIR` | For round trip unless `--pex-manifest` is used | Inline parasitic IR for post-layout simulation. |

## Name Rules

`name`, component names, net names, analysis source names, PEX corner IDs, PEX element IDs, and PEX node names must be stable single-token identifiers.

| Name kind | Allowed characters | Additional rejection |
|---|---|---|
| Design `name` | ASCII letters, digits, `.`, `_`, `-` | Empty, whitespace, `/`, `\`, `.`, `..` |
| Component names | ASCII letters, digits, `_` | Empty or whitespace |
| Net names | ASCII letters, digits, `_` | Empty or whitespace |
| Parameter names | ASCII letters, digits, `_` | Empty or whitespace |
| Analysis source | ASCII letters, digits, `_` | Empty or whitespace |
| PEX IDs/nodes/corners | ASCII letters, digits, `_` | Empty or whitespace |

Component names must also match the SPICE element prefix implied by `deviceKindID`.

| Device kind | Required prefix |
|---|---|
| `resistor` | `R` |
| `capacitor` | `C` |
| `inductor` | `L` |
| `vsource` | `V` |
| `isource` | `I` |
| `vcvs` | `E` |
| `vccs` | `G` |
| `ccvs` | `H` |
| `cccs` | `F` |
| `diode` | `D` |
| `npn`, `pnp` | `Q` |
| `nmos_l1`, `pmos_l1`, `nmos_l2`, `pmos_l2`, `nmos_l3`, `pmos_l3` | `M` |

## Components

| Field | Required | Meaning |
|---|---:|---|
| `name` | Yes | Instance name. Must be unique. |
| `deviceKindID` | Yes | Device kind from `DeviceCatalog.standard()`. |
| `parameters` | No | Numeric parameter overrides. Missing means `{}`. |
| `modelPresetID` | No | Optional model preset ID. |
| `modelName` | No | Optional explicit model name. |

Parameter names must exist in the selected device kind's parameter schema. Parameter values must be finite numbers and must satisfy the schema range when one is declared. Parameters marked required in the catalog must be present. Invalid, unknown, missing, non-finite, and out-of-range values are rejected before artifacts are produced.

`modelPresetID` and `modelName` are accepted only for device kinds with a `modelType`, and they are mutually exclusive. If `modelPresetID` is present, it must refer to a catalog preset whose `modelType` matches the selected device kind. If `modelName` is present, it must be a valid SPICE token.

## Nets

| Field | Required | Meaning |
|---|---:|---|
| `name` | Yes | Net name. Must be unique. |
| `terminals` | Yes | Component terminals owned by this net. |

Each terminal has:

| Field | Required | Meaning |
|---|---:|---|
| `component` | Yes | Component instance name. |
| `port` | Yes | Port ID from the component's device kind. |

A terminal may appear in only one net. Duplicate terminal ownership is rejected before artifacts are produced.

## Analyses

| Kind | Required fields | Optional fields |
|---|---|---|
| `op` | None | None |
| `tran` | `stopTime` | `stepTime`, `startTime`, `maxStep` |
| `dcSweep` | `source`, `startValue`, `stopValue`, `stepValue` | None |

Analysis values must be finite. `tran.stopTime` must be positive. Transient optional time values must be non-negative. DC sweep `stepValue` must be non-zero and move from `startValue` toward `stopValue`.

## Inline PEX IR

`pexIR` mirrors the subset needed by `PostLayoutSimulationService`.

| Field | Required | Meaning |
|---|---:|---|
| `version` | Yes | IR version string. |
| `cornerID` | Yes | Process corner ID. |
| `units` | No | Unit declarations. Missing values default to canonical units. |
| `elements` | Yes | R/C/coupling parasitic elements. |
| `diagnostics` | No | Optional imported diagnostics. |

Supported units:

| Quantity | Supported values | Canonical |
|---|---|---|
| resistance | `ohm`, `kohm` | `ohm` |
| capacitance | `F`, `pF`, `fF` | `F` |
| coordinate | `um` | `um` |

Inline PEX values are normalized to canonical units before post-layout simulation. Saved PEX manifests loaded with `--pex-manifest` use the same canonical `PEXParasiticIR` contract.

Supported element kinds:

| Kind | Node contract |
|---|---|
| `resistor` | `nodeA` and `nodeB` |
| `capacitor` | `nodeA`; `nodeB` may be omitted for ground-referenced capacitance |
| `coupling` | `nodeA` and `nodeB` |

Element IDs must be unique. Element values must be finite and positive.

## CLI Use

| Operation | Command |
|---|---|
| Netlist | `swift run circuit-studio-flow-runner --generate-netlist --design-spec <path>` |
| Simulation | `swift run circuit-studio-flow-runner --simulate --design-spec <path>` |
| Full round trip | `swift run circuit-studio-flow-runner --design-spec <path> --approve-signoff` |
| Design edit | `swift run circuit-studio-flow-runner --apply-design-edit --design-spec <path> --edit-script <path> --output-design-spec <path>` |
| Bottleneck summary | `swift run circuit-studio-flow-runner --summarize-bottlenecks --design-spec <path>` |

When `--output` is omitted, design-spec round trips use `./round-trip-runs/<design-spec-file-name-without-extension>`.

The round-trip manifest records the original spec as:

| Manifest artifact | Meaning |
|---|---|
| `kind: design-spec` | Captured copy under `input-artifacts/design/` |
| `sourcePath` | Original source path passed to `--design-spec` |

## Design Edit Script

`--apply-design-edit` applies a Codable edit script to an existing design spec and writes three audit artifacts:

| Artifact | Meaning |
|---|---|
| Edited design spec | The output JSON passed to `--output-design-spec`. |
| `actions.jsonl` | One applied edit action per line. |
| `design-diff.json` | Component and net additions, removals, and changes. |

Supported edit kinds:

| Kind | Required fields | Optional fields |
|---|---|---|
| `placeComponent` | `componentName`, `deviceKindID` | `parameters`, `modelPresetID`, `modelName` |
| `removeComponent` | `componentName` | None |
| `renameComponent` | `componentName`, `newComponentName` | None |
| `setComponentParameters` | `componentName`, `parameters` | `modelPresetID`, `modelName` |
| `connectNet` | `netName`, `terminal` | None |
| `disconnectTerminal` | `netName`, `terminal` | None |

The edited spec is validated with the same builder used by simulation and round-trip commands before artifacts are returned.

## Current Limits

| Limit | Impact |
|---|---|
| Schema version `1` only | Future incompatible changes must increment `schemaVersion`. |
| Device kinds come from `DeviceCatalog.standard()` | Custom PDK/device catalog injection is not exposed in this CLI contract yet. |
| Geometry is auto-generated | The spec describes circuit intent, not hand-authored layout. |
| Inline PEX is optional only when `--pex-manifest` is supplied | Full round trip needs parasitics from one of those two sources. |
| No subcircuits or hierarchy | Current contract builds one flat schematic. |
| Edit scripts target design specs only | Layout-edit, approval, and rerun commands are separate future command surfaces. |
