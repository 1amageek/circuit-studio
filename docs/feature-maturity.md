# CircuitStudio Feature Maturity

Last evaluated: 2026-05-07

この評価は、`circuit-studio` を Agent API としてではなく、人間が操作する統合 cockpit として見た個別機能の完成度を記録する。

## 評価基準

| Score | Meaning |
|---:|---|
| 0 | 未実装 |
| 1 | 型や骨格のみ |
| 2 | 基本動作あり、検証不足 |
| 3 | 代表ケースがテスト済み |
| 4 | 統合フローが動き、失敗系も検証済み |
| 5 | 実運用相当、互換性・例外・回帰が十分 |

## Verification Summary

| Target | Command | Result |
|---|---|---|
| CircuitStudio build | `perl -e 'alarm 120; exec @ARGV' swift build` | Pass |
| CircuitStudio core tests | `perl -e 'alarm 120; exec @ARGV' swift test --filter CircuitStudioCoreTests` | 140 pass, 4 skipped |
| Standalone voltage-divider round trip | `perl -e 'alarm 120; exec @ARGV' swift run circuit-studio-flow-runner --fixture voltage-divider --output /tmp/circuit-studio-cli-roundtrip-vd --run-id vd-cli` | Pass |
| Standalone CMOS inverter round trip | `perl -e 'alarm 120; exec @ARGV' swift run circuit-studio-flow-runner --fixture cmos-inverter --output /tmp/circuit-studio-cli-roundtrip-cmos --run-id cmos-cli` | Pass |
| Standalone voltage-divider round trip with golden PEX artifact | `perl -e 'alarm 120; exec @ARGV' swift run circuit-studio-flow-runner --fixture voltage-divider --pex-manifest Tests/CircuitStudioCoreTests/Fixtures/pex/golden-voltage-divider/manifest.json --pex-corner tt_25c_1v0 --output /tmp/circuit-studio-cli-roundtrip-vd-golden-pex --run-id vd-golden-pex-cli` | Pass |
| Standalone voltage-divider round trip with golden signoff and PEX artifacts | `perl -e 'alarm 120; exec @ARGV' swift run circuit-studio-flow-runner --fixture voltage-divider --signoff-drc-log Tests/CircuitStudioCoreTests/Fixtures/signoff/golden-calibre-drc-clean.log --signoff-lvs-log Tests/CircuitStudioCoreTests/Fixtures/signoff/golden-calibre-lvs-clean.log --pex-manifest Tests/CircuitStudioCoreTests/Fixtures/pex/golden-voltage-divider/manifest.json --pex-corner tt_25c_1v0 --output /tmp/circuit-studio-cli-roundtrip-vd-golden-signoff-pex --run-id vd-golden-signoff-pex-cli` | Pass |
| Standalone voltage-divider round trip with post-layout comparison | `perl -e 'alarm 120; exec @ARGV' swift run circuit-studio-flow-runner --fixture voltage-divider --signoff-drc-log Tests/CircuitStudioCoreTests/Fixtures/signoff/golden-calibre-drc-clean.log --signoff-lvs-log Tests/CircuitStudioCoreTests/Fixtures/signoff/golden-calibre-lvs-clean.log --pex-manifest Tests/CircuitStudioCoreTests/Fixtures/pex/golden-voltage-divider/manifest.json --pex-corner tt_25c_1v0 --output /tmp/circuit-studio-cli-roundtrip-vd-comparison --run-id vd-comparison-cli` | Pass |
| CoreSpice IR | `perl -e 'alarm 120; exec @ARGV' swift test --filter CoreSpiceIRTests` | 29 pass |
| semiconductor-layout IO | `perl -e 'alarm 120; exec @ARGV' swift test --filter LayoutIOTests` | 65 pass |
| swift-mask-data detector | `perl -e 'alarm 120; exec @ARGV' swift test --filter FormatDetectorTests` | 28 pass |
| PEXEngine runtime | `perl -e 'alarm 120; exec @ARGV' swift test --filter PEXRuntimeTests` | 16 pass |

Skipped CircuitStudio tests are explicit known limitations:

| Test | Reason |
|---|---|
| `J3: BJT with .model card` | NR solver lacks damping for nonlinear BJT convergence |
| `J4: MOSFET with .model card` | NR solver lacks damping for nonlinear MOSFET convergence |
| `J6: SIN voltage source transient` | Transient solver timestep control collapses with SIN waveforms |
| `J9: Parameter expression evaluation` | SPICE parser does not yet support `.param` expression evaluation |

## Feature Maturity Matrix

| Feature | Score | Implemented | Confirmed by tests | Weak / unverified | Next tests |
|---|---:|---|---|---|---|
| Schematic model/editor operations | 3 | `SchematicDocument`, component placement model, wires, labels, junctions, selection, undo/redo, mirror, copy/paste, T-junction wire splitting | `SchematicViewModelTests`, `UndoStackTests`, `MirrorTests`, `SelectionTests`, `CopyPasteTests` | Interactive canvas gestures, NoConnect/power-symbol style workflows, ERC-level checks | Add gesture-level editor tests and ERC-oriented connectivity diagnostics |
| Device catalog / symbol metadata | 4 | Standard device catalog, categories, ports, parameter schemas, semiconductor model classification | `DeviceCatalogTests` | Symbol rendering fidelity and full SPICE model coverage are not exhaustively checked | Add snapshot/geometry tests for symbols and model preset coverage tests |
| Net extraction | 4 | Union-Find based net extraction, pin/wire connectivity, ground net handling, label naming/merging, endpoint-to-segment T-junctions, overlapping collinear wires | `NetExtractorTests` | Larger schematics, conflicting labels, floating nets, non-axis-aligned imported wires | Add conflicting-label diagnostics and larger multi-branch imported-schematic cases |
| Netlist generation | 4 | SPICE generation for passive, controlled source, diode, BJT, MOSFET, tran/ac directives, process headers | `NetlistGeneratorTests`, parts of `EndToEndTests` | Advanced SPICE syntax, `.param` expressions, subcircuits, include ordering edge cases | Add parser/generator round-trip tests and expression/subckt coverage |
| Process configuration / Virtual PDK | 4 | Process libraries, includes, corner overrides, global parameters, temperature, fixture-backed virtual PDK | `ProcessConfigurationTests`, `VirtualPDKTests` | Multiple PDK layouts, missing libraries, conflicting corner sections, relative path portability | Add missing-file diagnostics and multi-corner include resolution tests |
| SimulationService | 3 | In-process CoreSpice execution, explicit analysis command execution, OP/AC/tran paths, event stream surface | `SimulationServiceTests`, `EndToEndTests` | Nonlinear convergence limitations, SIN transient limitation, `.param` expression limitation, cancellation not covered here | Add convergence failure classification, cancellation, and structured diagnostic tests |
| WaveformViewer | 3 | Waveform document, traces, chart view, toolbar, trace visibility, streaming updates, zoom/pan/cursor, terminal filtering, complex magnitude display | `WaveformViewModelTests` | Chart rendering, AppKit scroll capture, export panel, large waveform decimation performance | Add chart interaction tests, export error tests, and large dataset decimation tests |
| ProjectService / standard file handling | 3 | Project creation, `.xcircuite` files, workspace/placement/simulation JSON, SPICE save paths, PEX config paths and TOML rendering | `ProjectServiceTests` | Layout export, overwrite policy, invalid JSON/load errors, absolute path normalization | Add temp-directory tests for layout export, invalid project files, and absolute path handling |
| Layout integration | 3 | `CircuitStudioApp` depends on `LayoutEditor`, `LayoutAutoGen`, `LayoutCore`, `LayoutTech`, `LayoutIO`, `LayoutVerify`; auto layout now preserves one-terminal physical nets as top-level boundary pins and avoids simple horizontal M1 shorts in passive round trips | `swift build`, `HeadlessRoundTripServiceTests`; lower-level `LayoutIOTests` pass | Full interactive layout editing workflow and cross-probe behavior are still lightly covered | Add app/service integration tests around loading layout, displaying violations, and cross-probe state |
| Headless round-trip harness | 4 | `HeadlessRoundTripService` runs schematic net extraction, SPICE generation, pre-layout simulation, auto layout, external signoff command execution or imported signoff review loading, persisted signoff approval, strict pre-PEX verification, PEX IR injection, post-layout simulation, pre/post waveform comparison, and writes a machine-readable manifest with artifacts, PEX input artifact paths, comparison report path, and gate status; failed gates now persist manifests with failed/skipped stage state before throwing; `circuit-studio-flow-runner` exposes the voltage-divider and CMOS-inverter pass paths as a standalone command-line entrypoint and can load saved signoff logs plus a saved PEX manifest/IR | `HeadlessRoundTripServiceTests` covers CMOS inverter transient, voltage divider OP, imported signoff review, comparison artifact, pre-PEX failure, empty PEX IR failure, and post-layout simulation failure; `swift run circuit-studio-flow-runner --fixture voltage-divider`, `swift run circuit-studio-flow-runner --fixture cmos-inverter`, the golden PEX manifest CLI run, the golden signoff+PEX CLI run, and the comparison CLI run pass | Real PEX backend and real signoff decks are still mock-backed; failure manifests are covered for headless harness gates but not real-tool corpus failures; comparison currently reports deltas but does not enforce tolerances | Add real PEX backend smoke tests, real signoff deck smoke tests, broader circuit fixtures, and tolerance-based comparison gates |
| Full LVS / DRC preflight | 4 | `PhysicalVerificationService`, DRC violation summaries, schematic-to-layout DesignUnit checks, stale-layout detection, actual layout instance validation, physically realized net validation, hierarchy topology error reporting, hierarchical connectivity extraction through shapes/vias/cut-shapes/pins/labels/instance pins, physical short/open detection, terminal mismatch reporting, explicit Full LVS skip diagnostics, missing/misnamed external port detection, invalid imported terminal reporting, duplicate imported terminal reporting, metadata-backed polygon terminal recognition, raw MOS `ACTIVE ∩ POLY` extraction, source/drain/gate/bulk terminal inference for current sample-process fixtures, numeric GDS layer alias normalization, shared-diffusion two-device extraction, raw resistor extraction, MOS W/L/kind/`nf` comparison, resistor value comparison, external signoff command execution, log artifact capture, existing signoff log import, report normalization, imported review injection into the headless pre-PEX gate, approval persistence, and explicit human approval gating before PEX | `PhysicalVerificationServiceTests`, `ExternalSignoffCommandServiceTests`, `ExternalSignoffArtifactServiceTests`, `HeadlessRoundTripServiceTests`, `CMOSInverterFlowTests`; lower-level `LayoutIOTests` pass | Real foundry PDK extraction rules, golden GDS/OASIS regression corpora, real signoff deck fixtures, and UI review workflows are not implemented | Add foundry-style extraction deck fixtures, golden GDS/OASIS corpus tests, real signoff deck smoke tests, and review UI approval tests |
| PEX command / artifact integration | 4 | `PEXCommandService`, `PEXProjectConfig`, PEX config paths, explicit executable invocation, extract argument building, stderr/non-zero mapping, manifest and IR artifact loading, unit normalization, dropped-element diagnostics, mock PEXEngine artifact handoff, and golden PEX manifest/IR/raw/log fixture loading | `PEXCommandServiceTests`, `PEXArtifactServiceTests`; lower-level `PEXRuntimeTests` pass | UI review flow, real-backend extractor flow, and PATH/`PEXENGINE_BIN` discovery isolation are not covered | Add UI review integration, real backend smoke tests, and environment discovery tests |
| Post-layout simulation | 4 | `PostLayoutSimulationService` merges base SPICE and unit-normalized PEX parasitic IR, renders extracted R/C/Ccoupling elements, runs CoreSpice analysis, and `PostLayoutComparisonService` records pre/post common-variable deltas | `PostLayoutSimulationServiceTests`, `HeadlessRoundTripServiceTests`, `CMOSInverterFlowTests` | Model/subckt-aware parasitic insertion, corner sweeps, tolerance gating, and large PEX deck performance are not covered | Add tolerance-based pre/post gates and multi-corner post-layout simulation tests |

## Current Read

```mermaid
flowchart LR
  Core["Core model / catalog"] --> Netlist["Net extraction / netlist"]
  Netlist --> Sim["Simulation"]
  Sim --> Wave["Waveform review"]
  Core --> Project["Project files"]
  Project --> Harness["Headless round-trip manifest"]
  Project --> Verify["DRC / LVS preflight"]
  Verify --> PEX["PEX integration"]
  PEX --> Post["Post-layout simulation"]
  Project --> Layout["Layout integration"]
```

The strongest `circuit-studio` areas are model/catalog, netlist generation, process configuration, and representative simulation flows. The DRC/LVS/PEX/post-layout path now has a strict headless round-trip harness that carries both a CMOS inverter and a voltage divider through artifact-producing stages without forced continuation, failed gates leave manifests for agent/human review, externally produced signoff logs can be imported into the same approval gate, the pass-path corpus can be run from the standalone `circuit-studio-flow-runner` CLI, and the voltage-divider CLI path can consume saved golden signoff logs plus a saved golden PEX manifest/IR artifact while recording those input artifacts and pre/post waveform deltas in the manifest. Real foundry decks, real extractor backends, broader circuit fixtures, tolerance gates, and multi-corner post-layout review are still future work.

## Recommended Next Work

| Priority | Work |
|---:|---|
| 1 | Add real foundry signoff deck fixtures and golden GDS/OASIS regression corpora |
| 2 | Add real PEX backend smoke tests and tolerance-based pre/post waveform gates across PEX corners |
| 3 | Add more small circuit fixtures beyond CMOS inverter and voltage divider |
| 4 | Add SimulationService failure/cancellation tests with structured diagnostic expectations |
| 5 | Add ProjectService follow-up tests for layout export, invalid project files, and absolute path handling |
| 6 | Track CoreSpice nonlinear convergence and `.param` expression limitations as upstream blockers |
