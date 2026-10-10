import CoreSpice
import CoreSpiceIO

/// Finite Application-selected operational ceilings, independent of device physics qualification.
enum StudioNativeExecutionPolicy {
    static let profile = MOSInputProfile.pinnedNgspiceNormalV1
    static let seed: UInt64 = 0
    static func resolutionLimits() throws -> MOSResolutionLimits {
        try .init(maximumRetainedBytes: 64 * 1024 * 1024, maximumDiagnosticBytes: 64 * 1024,
            maximumScopeDepth: 64, maximumSymbols: 65536, maximumScopes: 4096,
            maximumInvocations: 16384, maximumInvocationBindings: 65536,
            maximumDeclarations: 16384, maximumPrograms: 262144, maximumBindings: 65536,
            maximumFunctions: 4096, maximumFunctionDepth: 64, maximumExpressionNodes: 1048576,
            maximumExpressionDepth: 256, maximumCandidates: 16384, maximumCacheEntries: 262144,
            maximumEvaluationSteps: 1000000000)
    }
    static var numericalLimits: TransientExecutionLimits {
        .init(maximumAcceptedSteps: 100000, maximumSolveAttempts: 200000,
            maximumNewtonIterations: 2000000, maximumSavedScalars: 4000000,
            maximumMatrixDimension: 256, maximumWorkUnits: 1000000000, maximumBreakpoints: 100000)
    }
    static func resources() throws -> SPICESimulationResources {
        let liveBytes: UInt64 = 2_147_483_648
        let temporaryBytes: UInt64 = 1_073_741_824
        let hashedBytes: UInt64 = 67_108_864
        return try SPICESimulationResources(maximumLiveBytes: liveBytes,
            maximumTemporaryBytes: temporaryBytes, maximumWorkUnits: 1_000_000_000,
            maximumHashedBytes: hashedBytes)
    }
    static func nativeLimits(options: SPICEAnalysisOptions, capabilities: MOSAnalysisCapabilities,
        maximumDeviceCount: Int = 16384, maximumMatrixDimension: Int = 512,
        maximumAllocationBytes: UInt64 = 1024 * 1024 * 1024) throws -> SPICENativeExecutionLimits {
        let operating = try options.operatingConditions()
        let conditions = try MOSPreparationConditions(ambientKelvin: operating.temperatureKelvin,
            nominalKelvin: operating.nominalTemperatureKelvin, analysisCapabilities: capabilities,
            maximumStressIterations: options.bsim4PreparationPolicy?.maximumStressIterations ?? 1)
        return .init(maximumDeviceCount: maximumDeviceCount, maximumMatrixDimension: maximumMatrixDimension,
            maximumAllocationBytes: maximumAllocationBytes,
            mosPreparationLimits: try .init(maximumRetainedBytes: 1024 * 1024,
                maximumTemporaryBytes: 1024 * 1024, maximumDiagnosticBytes: 65536, maximumWorkUnits: 1000000),
            mosPreparationConditions: conditions)
    }
}
