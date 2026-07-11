import Activity
import Foundation
import SwiftUI

public struct ActivityTimelineView: View {
    public let projectRoot: URL
    public let activityService: ActivityService
    public let selectRun: (String) -> Void

    @State private var activities: [Activity] = []
    @State private var isLoading = false
    @State private var loadError: String?

    public init(
        projectRoot: URL,
        activityService: ActivityService,
        selectRun: @escaping (String) -> Void = { _ in }
    ) {
        self.projectRoot = projectRoot
        self.activityService = activityService
        self.selectRun = selectRun
    }

    public var body: some View {
        List {
            if let loadError {
                ContentUnavailableView(
                    "Activity is unavailable",
                    systemImage: "clock.badge.exclamationmark",
                    description: Text(loadError)
                )
            } else if activities.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "clock",
                    description: Text("Recorded design operations will appear here.")
                )
            } else {
                ForEach(activities) { activity in
                    ActivityTimelineRow(activity: activity, selectRun: selectRun)
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh activity")
                .disabled(isLoading)
            }
        }
        .task(id: projectRoot) {
            await reload()
        }
    }

    private func reload() async {
        guard !Task.isCancelled else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await activityService.reconcile(projectRoot: projectRoot)
            activities = try await activityService.activities(
                forProjectAt: projectRoot,
                query: ActivityQuery(limit: 500)
            )
            loadError = nil
        } catch {
            activities = []
            loadError = error.localizedDescription
        }
    }
}

private struct ActivityTimelineRow: View {
    let activity: Activity
    let selectRun: (String) -> Void

    var body: some View {
        if let runID = activity.runID {
            Button {
                selectRun(runID)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: activity.systemImage)
                .foregroundStyle(activity.statusColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(activity.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(activity.occurredAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(activity.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(activity.kind)
                    Text(activity.actorIdentifier)
                    if !activity.artifacts.isEmpty || activity.omittedArtifactCount > 0 {
                        Text("\(activity.artifacts.count + activity.omittedArtifactCount) artifacts")
                    }
                    if !activity.diagnostics.isEmpty || activity.omittedDiagnosticCount > 0 {
                        Text("\(activity.diagnostics.count + activity.omittedDiagnosticCount) diagnostics")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private extension Activity {
    var systemImage: String {
        switch status {
        case .running: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .blocked: return "pause.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .informational: return "info.circle"
        }
    }

    var statusColor: Color {
        switch status {
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled, .blocked: return .orange
        case .partial: return .yellow
        case .informational: return .secondary
        }
    }
}
