import Foundation
import SwiftUI

public struct ReviewWorkspaceView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case activity = "Activity"
        case runs = "Runs"

        var id: String { rawValue }
    }

    public let projectRoot: URL
    public let services: ServiceContainer

    @State private var mode: Mode = .activity
    @State private var selectedRunID: String?

    public init(projectRoot: URL, services: ServiceContainer) {
        self.projectRoot = projectRoot
        self.services = services
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Review view", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch mode {
            case .activity:
                ActivityTimelineView(
                    projectRoot: projectRoot,
                    activityService: services.activityService,
                    selectRun: { runID in
                        selectedRunID = runID
                        mode = .runs
                    }
                )
            case .runs:
                RunReviewView(
                    projectRoot: projectRoot,
                    reviewer: NSUserName(),
                    initialRunID: selectedRunID
                )
                .id(selectedRunID ?? "latest")
            }
        }
        .navigationTitle("Review")
    }
}
