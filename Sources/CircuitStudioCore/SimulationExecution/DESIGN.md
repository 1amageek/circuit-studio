# SimulationExecution

## Purpose and Scope

Own the native simulation service lifecycle and caller-selected transient execution
policy. Parent: [CircuitStudioCore](../DESIGN.md). No child design units.

## Responsibilities and Boundaries

SimulationService parses/lowers/compiles/binds through CoreSpice public contracts,
selects a caller or complete deck policy and propagates execution results/failures.
CoreSpice owns numerical execution and admission; this component owns no solver,
capacity discovery, Metal backend, qualification or canonical storage.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CircuitStudioCore](../DESIGN.md) | parent | SimulationRunning and SimulationResult | Typed application simulation | Completion is not signoff qualification |
| [CoreSpice IO](../../../../CoreSpice/Sources/CoreSpiceIO/DESIGN.md) | depends on | SPICEAnalysisOptions provenance and transientConfig | Exact parsed deck options | Partial limits cannot be completed with an application preset |
| [CoreSpice Analysis](../../../../CoreSpice/Sources/CoreSpiceAnalysis/DESIGN.md) | depends on | TransientExecutionLimits and typed execution errors | Budgeted CPU MNA | DC initialization and retries consume the same budget |

## Architecture

```text
App/test composition -> explicit immutable caller limits or explicit nil
SPICE source -> existing parser -> SPICEAnalysisOptions
    -> complete deck limits / absent deck caller limits / partial deck failure
    -> one TransientExecution(config + exact policy provenance)
    -> CoreSpice CPU MNA -> waveform + SimulationResult policy
```

## Contracts and Invariants

SimulationService initialization explicitly supplies optional transient limits.
There is no omitted/default initializer policy. App composition selects the named
StudioTransientExecutionPolicy.interactivePreview preset; typed callers can select
other positive limits or explicitly nil. A complete seven-field deck policy has
priority over caller limits. Any partial deck policy fails as missingExecutionLimits
without caller fallback. With no deck policy, missing caller limits also fail before
transient polling/analysis starts. Deck timestep/integration options are translated
by SPICEAnalysisOptions, never reparsed or reconstructed here. Parsed convergence
options also configure the native transient solver through that same owner.
Options reported as unapplied retain their diagnostics in result logMessages.
Scalar metadata queries do not coerce numeric vectors. CoreSpice options admission
validates temperature controls before native transient execution.

The admitted TransientConfig and result policy share the exact same selected limits.
The result retains the source (caller/deckOptions) and all seven values. Invalid,
missing and exhausted limits propagate as typed CoreSpice errors; failed or cancelled
analysis cannot return completed. AnalysisError.cancelled and Swift cancellation
become StudioError.cancelled and a cancelled terminal event. Polling stops and is
awaited before returning or throwing.

## State, Ownership, and Lifecycle

Job state and event continuations remain in the existing Mutex<State>. Cancellation,
continuation emission and external callbacks run outside the lock. Immutable limits
belong to the service instance; an admitted execution belongs to one invocation.
Shutdown finishes continuations and cancels active tokens through the existing owner.
No target-dependent synchronization or shared mutable policy is added.

## Failure, Concurrency, and Constraints

The application operational preset owns ceilings of 100,000 accepted steps, 200,000
solve attempts, 2,000,000 Newton iterations, 4,000,000 saved scalars, matrix dimension
256, 1,000,000,000 work units and 100,000 breakpoints. These are finite application
choices, not discovered machine capacity or universal completion guarantees. Caller
limits must be positive; CoreSpice checks dimension, cumulative budgets and arithmetic.
The numeric saved payload alone is bounded by scalar count times Double stride;
streaming buffers, waveform copies and LU factors also use memory, so no RSS guarantee
is made. A larger application policy is an explicit composition change and requires
rerunning numerical success and bounded failure fixtures. No automatic policy increase
or backend substitution occurs on failure.

## Verification and Change Impact

[SimulationServiceExecutionTests](../../../Tests/CircuitStudioCoreTests/SimulationServiceExecutionTests.swift)
proves explicit caller limits, exact complete deck precedence, partial/missing/low limit
failure and actual transient cancellation. [EndToEndTests](../../../Tests/CircuitStudioCoreTests/EndToEndTests.swift)
proves expected waveform values through parser/compiler/device/CPU analysis. Existing
SimulationService lifecycle tests cover stream shutdown and active-job cleanup. Changing
preset values, source precedence, failure routing or transient options requires these
focused timeout-bounded checks. This change claims CPU macOS execution, not GPU,
WASM/Embedded, external ngspice or signoff qualification.
