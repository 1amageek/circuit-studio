import CoreSpice

/// Finite application-selected CPU execution ceilings, not a machine-capacity guarantee.
public enum StudioTransientExecutionPolicy {
    /// Used explicitly by application composition for interactive native transient analysis.
    public static var interactivePreview: TransientExecutionLimits {
        TransientExecutionLimits(
            maximumAcceptedSteps: 100_000,
            maximumSolveAttempts: 200_000,
            maximumNewtonIterations: 2_000_000,
            maximumSavedScalars: 4_000_000,
            maximumMatrixDimension: 256,
            maximumWorkUnits: 1_000_000_000,
            maximumBreakpoints: 100_000
        )
    }
}
