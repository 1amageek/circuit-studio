# CircuitStudioCore

## Purpose and Scope

Own application design values and simulation/service contracts. Parent:
[Circuit Studio](../../DESIGN.md). Child:
[SimulationExecution](SimulationExecution/DESIGN.md).

## Responsibilities and Boundaries

Provide typed developer/application operations and projections. CoreSpice owns
numerics; domain packages own their canonical semantics. This change owns transient
caller policy composition and result/failure projection, not domain storage or trust.

The existing [SPICESchematicImporter](Services/SPICESchematicImporter.swift) owns
scalar schematic projection. Vector parameters are not representable by its scalar
parameter schema. Preflight rejects any selected component containing a numeric
vector with typed unsupportedComponents before materializing a document; a vector
source must never become a default DC source. Vector schematic support requires
lossless projection and netlist serialization and remains incomplete.
Scalar waveform projection selects amplitude fields from the parsed source kind:

| Shared schematic field | Voltage source field | Current source field |
|---|---|---|
| pulse_v1 / pulse_v2 | v1 / v2 | i1 / i2 |
| sin_vo / sin_va | vo / va | io / ia |

The existing schematic source kind owns amplitude units and serialization. Required
amplitudes are projected from explicit parsed values rather than device defaults.
NetlistParsingService exposes a lightweight scalar primary-value summary. Numeric
vectors have no scalar primary value; the summary never fabricates a DC value.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Circuit Studio](../../DESIGN.md) | parent | Cockpit projections | Human/developer interaction | UI completion is scoped evidence |
| [SimulationExecution](SimulationExecution/DESIGN.md) | child | SimulationRunning and exact transient policy result | Native simulation | Preserve complete deck policy and typed failures |

## Architecture

```text
Application composition -> SimulationRunning -> SimulationExecution -> CoreSpice
    -> SimulationResult / typed failure -> human/developer projection
```

## Contracts and Invariants

PEXExtractionService projects the actual PEXRunning result. Only a successful run
and successful selected corner with canonical IR become PEXExtractionResult.
Failed or partially successful runs and failed selected corners throw
PEXExtractionError.executionFailed carrying the complete PEXRunResult, including
the manifest URL, observed producer, captured inputs and backend diagnostics.
missingCorner describes only a successful run missing the requested canonical
corner. PEXRuntime owns native reference loading and bounded input admission;
Studio does not decode, rewrite or synthesize native configuration/calibration.
Explicit caller executable overrides resolve against the caller's current directory
before replacing a persisted document-relative executable path. GUI uses the saved
config and does not resubmit a project-view executable as an override.

```text
JSON config + explicit path context -> PEXConfigMapper -> PEXRunning
    -> success + canonical corner -> PEXExtractionResult
    -> failed run/corner -> executionFailed(actual PEXRunResult)
```

Transient callers explicitly select an operational policy. Completed native transient
results retain its exact provenance. Missing, partial and exhausted policy cannot be
projected as completed. Component contracts own detailed admission and lifecycle rules.

## Verification and Change Impact

[StudioNativePEXConfigurationTests](../../Tests/CircuitStudioCoreTests/StudioNativePEXConfigurationTests.swift)
owns native config composition through the actual default engine, retained
canonical/standard artifacts, native input absence and retained backend failure.
Its single two-port analytical sheet fixture defines a nonproduction law; it
does not establish process accuracy or foundry qualification. Existing injected
runner tests continue to prove dependency injection, not native extraction.

SimulationServiceExecutionTests, EndToEndTests and SimulationServiceTests own the
native CPU numerical and lifecycle proofs. Composition changes must preserve the
component's policy and failure contract. External simulators remain a separate backend.

[SPICESchematicImporterLayoutTests](../../Tests/CircuitStudioCoreTests/SPICESchematicImporterLayoutTests.swift)
proves vector-source refusal and existing scalar/PULSE projection success. Parsed
value additions require rechecking this boundary with the simulation component.
[NetlistParsingServiceTests](../../Tests/CircuitStudioCoreTests/NetlistParsingServiceTests.swift)
checks actual PWL parsing without scalar coercion alongside a scalar resistor value.
