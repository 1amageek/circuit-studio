# CircuitStudioApp

## Purpose and Scope

Own the application composition and command/UI entry points. Parent:
[Circuit Studio](../../DESIGN.md). Child:
[ProjectConfiguration](ProjectConfiguration/DESIGN.md).

## Responsibilities and Boundaries

Compose developer commands and human actions with typed Core/domain services.
ProjectService remains the filesystem platform adapter in Services. Domain
engines own calculations, native admission, provenance and retained artifacts.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Circuit Studio](../../DESIGN.md) | parent | Cockpit composition | Application boundary | Display is not qualification |
| [ProjectConfiguration](ProjectConfiguration/DESIGN.md) | child | Persisted executable PEX JSON config | Project filesystem adapter | Preserve document path authority |
| [CircuitStudioCore](../CircuitStudioCore/DESIGN.md) | depends on | PEXExtractionService and typed failures | Shared command/UI extraction | Retain actual failed run |

## Architecture

```text
ProjectService -> .xcircuite/pex.json
GUI / DesignFlowCommand.runPEXExtraction -> DesignFlowService
    -> PEXExtractionService -> PEXRuntime / actual backend
```

## Contracts and Invariants

Command and GUI extraction use the same Core extraction service. Native config
selection is explicit and persisted. Engine failure must not become a successful
command or be reduced to absent-corner evidence.

## Verification and Change Impact

StudioNativePEXConfigurationTests owns the native ingestion boundary through
actual command and CLI execution. Native numerical qualification remains in
PEXEngine. Recheck both caller path contexts when changing persisted paths.
