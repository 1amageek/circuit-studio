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
SPICE source + optional typed analysis -> existing parser -> SPICEAnalysisOptions
    -> explicit process temperature priority / typed noise intent
    -> one lowering session + deviceRegistry + operatingConditions
    -> immutable Pipeline + consumed PreparedNativeCircuit
    -> DC source-only updates preserve prepared device state
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
validates temperature controls for every native analysis. ProcessConfiguration
retains its existing temperature priority: explicit override, selected corner,
technology, deck, CoreSpice nominal. That selected temperature updates the resolved
options before both lowering and operatingConditions; no separate temperature
parser remains. Parameter overrides remain a lowering-only process contract.

The pipeline resolves deck options once. Its registry and operating conditions are
created once and passed to the domain preparation owner. DC source updates retain
that prepared owner without repeating MOS setup. Level54
preparation policy is the explicit deck policy; no application budget is fabricated.
Parsed noise intent and an explicit typed .noise command both request preparation
before lowering, including a typed command with no deck .noise directive. All
native analyses use the admitted convergence options, and unapplied diagnostics
retain their messages in the actual SimulationResult. Missing preparation policy
propagates as BSIM4DeviceError, rather than a successful/default model or a string
failure; other existing parser/compiler error routing and cancellation stay owned
by this service. The recorder consumes the actual result without reconstructing
policy or model intent.

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

[BSIM4SimulationCompositionTests](../../../Tests/CircuitStudioCoreTests/BSIM4SimulationCompositionTests.swift)
proves native Level54 OP and source-only DC sweeps, typed missing policy, explicit noise intent,
and shared selected temperature. This is public composition evidence; numerical
model qualification remains in CoreSpice.

## S4 Common Native Composition

The application compiles source once and owns one exclusive lowering session for
options, the selected static analysis command, process overrides and circuit emission.
It retains LoweredCircuit for inspection and asks CoreSpice NativeCircuitPreparer to
prepare, allocate auxiliary topology, compile and bind each invocation once. Pipeline
metadata is immutable; the numerical owner is consumed by a concrete Analysis operation.
DC sweeps use the domain source-only update operation and retain MOS cold preparation.
AC, noise, transfer-function and pole-zero analyses retain their existing public behavior.
Transient onStepAccepted still feeds the existing progress channel; success and failure
cancel and await polling before returning. Job and continuation isolation stays Mutex.

The named interactive native policy selects finite lowering/preparation/resource and
non-transient numerical ceilings. Complete deck transient ceilings retain precedence.
Selected process temperature and parameter overrides enter the sole frontend session;
preparation conditions use exact selected ambient/nominal values and requested analysis
capabilities. Source inventory and selection metadata are not completed execution facts.

Existing execution/composition tests cover physical output and cancellation; new MOS
fixtures cover family selection and repeated DC points without per-point cold setup.

### Source node voltage admission

The ordinary caller resolves initial conditions and node sets from canonical scalar
slots after circuit lowering and before consuming the same evaluation session.
Component operands, IC and nodeset expressions share one memo and random stream.
UIC transient applies exact initial node voltages. OP/DC apply node sets as Newton
guesses; ordinary transient applies them to its DC initialization. Initial conditions
without UIC and node sets on other analyses fail explicitly after expression evaluation.
Node sets with UIC also fail with the IO unsupportedCapability cause because UIC
skips the DC stage that applies those guesses; expressions still resolve before this
policy check, so undefined parameters keep their original typed failure.
Source errors
retain the IO node-voltage error and underlying typed evaluation cause.

The caller regression suites exercise UIC initial voltage, undefined IC and nodeset,
shared component-to-IC random order, and caller lifecycle cleanup. The source review
counterexample is retained in the task verification artifacts; runtime RED was not
executed while numerical dependencies were mutable. Public-path GREEN is required.
