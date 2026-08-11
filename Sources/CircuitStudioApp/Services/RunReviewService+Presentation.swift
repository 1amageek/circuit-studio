import DesignFlowKernel

extension RunReviewService {
    func circuitStudioPresentationBundle(
        _ bundle: FlowRunReviewBundle
    ) -> FlowRunReviewBundle {
        let pathsByAvailability = bundle.artifacts.reduce(into: [String: String]()) {
            paths, artifact in
            paths[artifact.binding.availabilityDescription] =
                artifact.binding.circuitStudioPresentationPath
        }
        func presentationPath(_ path: String) -> String {
            pathsByAvailability[path] ?? path
        }

        var presented = bundle
        for index in presented.reviewItems.indices {
            presented.reviewItems[index].artifactPaths = presented.reviewItems[index]
                .artifactPaths
                .map(presentationPath)
        }
        if var coverageRefs = presented.coverageRefs {
            for index in coverageRefs.indices {
                coverageRefs[index].path = coverageRefs[index].path.map(presentationPath)
            }
            presented.coverageRefs = coverageRefs
        }
        if var decisionActions = presented.decisionActions {
            for index in decisionActions.indices {
                decisionActions[index].targetPath = decisionActions[index]
                    .targetPath
                    .map(presentationPath)
            }
            presented.decisionActions = decisionActions
        }
        return presented
    }
}
