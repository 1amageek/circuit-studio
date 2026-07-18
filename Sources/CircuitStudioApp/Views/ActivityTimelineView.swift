import Activity
import Foundation
import SwiftUI

public struct ActivityTimelineView: View {
    public let projectRoot: URL
    public let activityService: ActivityService
    public let selectRun: (String) -> Void
    public let artifactResourceLoader: any RunReviewArtifactResourceLoading

    @State private var activities: [Activity] = []
    @State private var selectedGroupID: String?
    @State private var statusFilter: ActivityStatusFilter = .all
    @State private var actorFilter: ActivityActorFilter = .all
    @State private var kindFilter: ActivityKindFilter = .all
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var reconciliationError: String?

    public init(
        projectRoot: URL,
        activityService: ActivityService,
        selectRun: @escaping (String) -> Void = { _ in },
        artifactResourceLoader: any RunReviewArtifactResourceLoading = RunReviewArtifactResourceLoader()
    ) {
        self.projectRoot = projectRoot
        self.activityService = activityService
        self.selectRun = selectRun
        self.artifactResourceLoader = artifactResourceLoader
    }

    public var body: some View {
        NavigationSplitView {
            timelineSidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 480)
        } detail: {
            if let selectedGroup {
                ActivityGroupDetailView(
                    group: selectedGroup,
                    projectRoot: projectRoot,
                    selectRun: selectRun,
                    artifactResourceLoader: artifactResourceLoader
                )
            } else {
                ContentUnavailableView(
                    "Select an activity",
                    systemImage: "clock",
                    description: Text("Choose an operation from the timeline.")
                )
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                filterMenu
            }
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
        .overlay {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: projectRoot) {
            await reload()
        }
        .onChange(of: filterSignature) { _, _ in
            ensureSelection()
        }
    }

    private var timelineSidebar: some View {
        List(selection: $selectedGroupID) {
            if let loadError {
                ContentUnavailableView(
                    "Activity is unavailable",
                    systemImage: "clock.badge.exclamationmark",
                    description: Text(loadError)
                )
            } else {
                if let reconciliationError {
                    Section {
                        Label("Activity index is degraded", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(reconciliationError)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Retry reconciliation") {
                            Task { await reload() }
                        }
                        .font(.caption)
                    }
                }

                if filteredGroups.isEmpty && !isLoading {
                    ContentUnavailableView {
                        Label(
                            hasActiveFilters ? "No matching activity" : "No activity yet",
                            systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "clock"
                        )
                    } description: {
                        Text(
                            hasActiveFilters
                                ? "Clear the filters to see all recorded operations."
                                : "Recorded design operations will appear here."
                        )
                    } actions: {
                        if hasActiveFilters {
                            Button("Clear filters", action: clearFilters)
                        }
                    }
                } else {
                    ForEach(ActivityTimelineSection.makeSections(from: filteredGroups)) { section in
                        Section(section.title) {
                            ForEach(section.groups) { group in
                                ActivityGroupRow(group: group)
                                    .tag(group.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Outcome", selection: $statusFilter) {
                ForEach(ActivityStatusFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }

            Picker("Actor", selection: $actorFilter) {
                ForEach(ActivityActorFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }

            Picker("Kind", selection: $kindFilter) {
                ForEach(ActivityKindFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }

            Divider()

            Button("Clear filters", action: clearFilters)
                .disabled(!hasActiveFilters)
        } label: {
            Label(
                "Filter",
                systemImage: hasActiveFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help("Filter activity")
    }

    private var filteredActivities: [Activity] {
        activities.filter { activity in
            statusFilter.matches(activity.status)
                && actorFilter.matches(activity.actorKind)
                && kindFilter.matches(activity)
        }
    }

    private var filteredGroups: [ActivityGroup] {
        ActivityGroup.makeGroups(from: filteredActivities)
    }

    private var selectedGroup: ActivityGroup? {
        guard let selectedGroupID else { return nil }
        return filteredGroups.first { $0.id == selectedGroupID }
    }

    private var hasActiveFilters: Bool {
        statusFilter != .all || actorFilter != .all || kindFilter != .all
    }

    private var filterSignature: String {
        "\(statusFilter.rawValue)|\(actorFilter.rawValue)|\(kindFilter.rawValue)"
    }

    private func clearFilters() {
        statusFilter = .all
        actorFilter = .all
        kindFilter = .all
    }

    private func ensureSelection() {
        let groups = filteredGroups
        guard let firstGroup = groups.first else {
            selectedGroupID = nil
            return
        }
        guard let selectedGroupID, groups.contains(where: { $0.id == selectedGroupID }) else {
            self.selectedGroupID = firstGroup.id
            return
        }
        self.selectedGroupID = selectedGroupID
    }

    private func reload() async {
        guard !Task.isCancelled else { return }
        isLoading = true
        defer { isLoading = false }

        var reconciliationFailure: String?
        do {
            _ = try await activityService.reconcile(projectRoot: projectRoot)
        } catch {
            reconciliationFailure = error.localizedDescription
        }

        do {
            let loadedActivities = try await activityService.activities(
                forProjectAt: projectRoot,
                query: ActivityQuery(limit: 2_000)
            )
            guard !Task.isCancelled else { return }
            activities = loadedActivities
            reconciliationError = reconciliationFailure
            loadError = nil
            selectedGroupID = ActivityGroup
                .makeGroups(from: filteredActivitiesForLoadedData(loadedActivities))
                .first?
                .id
        } catch {
            guard !Task.isCancelled else { return }
            activities = []
            selectedGroupID = nil
            reconciliationError = reconciliationFailure
            loadError = error.localizedDescription
        }
    }

    private func filteredActivitiesForLoadedData(_ loadedActivities: [Activity]) -> [Activity] {
        loadedActivities.filter { activity in
            statusFilter.matches(activity.status)
                && actorFilter.matches(activity.actorKind)
                && kindFilter.matches(activity)
        }
    }
}

private struct ActivityGroupRow: View {
    let group: ActivityGroup

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: group.status.systemImage)
                .foregroundStyle(group.status.statusColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer()
                    Text(group.latestActivity.occurredAt, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(group.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(group.actorLabel)
                    if let runID = group.runID {
                        Text(runID)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if group.artifactCount > 0 {
                        Label("\(group.artifactCount)", systemImage: "doc")
                    }
                    if group.diagnosticCount > 0 {
                        Label("\(group.diagnosticCount)", systemImage: "exclamationmark.bubble")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ActivityTimelineSection: Identifiable {
    let id: Date
    let title: String
    let groups: [ActivityGroup]

    static func makeSections(from groups: [ActivityGroup]) -> [ActivityTimelineSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: groups) { group in
            calendar.startOfDay(for: group.latestActivity.occurredAt)
        }
        return grouped
            .map { day, groups in
                ActivityTimelineSection(
                    id: day,
                    title: dayTitle(day, calendar: calendar),
                    groups: groups.sorted { lhs, rhs in
                        lhs.latestActivity.occurredAt > rhs.latestActivity.occurredAt
                    }
                )
            }
            .sorted { lhs, rhs in lhs.id > rhs.id }
    }

    private static func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.year().month().day().weekday(.wide))
    }
}

private struct ActivityGroupDetailView: View {
    let group: ActivityGroup
    let projectRoot: URL
    let selectRun: (String) -> Void
    let artifactResourceLoader: any RunReviewArtifactResourceLoading

    @State private var expandedEventIDs: Set<String> = []
    @State private var selectedArtifact: ActivityArtifactSelection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                groupHeader
                Divider()

                ForEach(group.activities) { activity in
                    eventView(activity)
                }
            }
            .padding()
        }
        .navigationTitle(group.title)
        .sheet(item: $selectedArtifact) { selection in
            ActivityArtifactPreview(
                projectRoot: projectRoot,
                activity: selection.activity,
                artifact: selection.artifact,
                artifactResourceLoader: artifactResourceLoader
            )
            .frame(minWidth: 760, minHeight: 560)
        }
    }

    private var groupHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: group.status.systemImage)
                    .foregroundStyle(group.status.statusColor)
                Text(group.title)
                    .font(.title2)
                    .bold()
                Text(group.status.title)
                    .font(.subheadline)
                    .foregroundStyle(group.status.statusColor)
                Spacer()
                if let runID = group.runID {
                    Button("Open Run", systemImage: "arrow.up.right") {
                        selectRun(runID)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Text(group.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Actor")
                        .foregroundStyle(.secondary)
                    Text(group.actorLabel)
                }
                GridRow {
                    Text("Time")
                        .foregroundStyle(.secondary)
                    Text(group.timeRange)
                }
                if let runID = group.runID {
                    GridRow {
                        Text("Run")
                            .foregroundStyle(.secondary)
                        Text(runID)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                GridRow {
                    Text("Evidence")
                        .foregroundStyle(.secondary)
                    Text("\(group.artifactCount) artifacts · \(group.diagnosticCount) diagnostics")
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func eventView(_ activity: Activity) -> some View {
        if activity.isLowSignal {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedEventIDs.contains(activity.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedEventIDs.insert(activity.id)
                        } else {
                            expandedEventIDs.remove(activity.id)
                        }
                    }
                )
            ) {
                eventDetails(activity)
                    .padding(.top, 8)
            } label: {
                eventHeader(activity)
            }
        } else {
            eventContent(activity)
        }
    }

    private func eventHeader(_ activity: Activity) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: activity.status.systemImage)
                .foregroundStyle(activity.status.statusColor)
                .frame(width: 18)
            Text(activity.title)
                .font(.headline)
            Text(activity.status.title)
                .font(.caption)
                .foregroundStyle(activity.status.statusColor)
            Spacer()
            Text(activity.occurredAt, format: .dateTime.year().month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func eventContent(_ activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            eventHeader(activity)
            eventDetails(activity)
        }
        .padding(.vertical, 8)
    }

    private func eventDetails(_ activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            Text(activity.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Text(activity.actorIdentifier)
                Text(activity.kind)
                if let stageID = activity.stageID {
                    Text(stageID)
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            if let command = activity.command {
                Text(([command.executable] + command.arguments).joined(separator: " "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            if !activity.artifacts.isEmpty || activity.omittedArtifactCount > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Artifacts")
                        .font(.caption)
                        .bold()
                    ForEach(Array(activity.artifacts.enumerated()), id: \.offset) { index, artifact in
                        artifactRow(
                            activity: activity,
                            artifact: artifact,
                            index: index
                        )
                    }
                    if activity.omittedArtifactCount > 0 {
                        Text("+\(activity.omittedArtifactCount) artifact references omitted")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !activity.diagnostics.isEmpty || activity.omittedDiagnosticCount > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Diagnostics")
                        .font(.caption)
                        .bold()
                    ForEach(Array(activity.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        Label {
                            Text("\(diagnostic.code): \(diagnostic.message)")
                        } icon: {
                            Image(systemName: "exclamationmark.bubble")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                    }
                    if activity.omittedDiagnosticCount > 0 {
                        Text("+\(activity.omittedDiagnosticCount) diagnostics omitted")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Source \(activity.sourceKind.rawValue) · revision \(activity.sourceRevision)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    private func artifactRow(
        activity: Activity,
        artifact: Activity.Artifact,
        index: Int
    ) -> some View {
        Group {
            if activity.runID != nil {
                Button {
                    selectedArtifact = ActivityArtifactSelection(
                        activity: activity,
                        artifact: artifact,
                        index: index
                    )
                } label: {
                    artifactLabel(artifact)
                }
                .buttonStyle(.plain)
            } else {
                artifactLabel(artifact, showsOpenIcon: false)
            }
        }
    }

    private func artifactLabel(
        _ artifact: Activity.Artifact,
        showsOpenIcon: Bool = true
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: artifact.direction.systemImage)
                .foregroundStyle(artifact.direction.statusColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.displayName)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(artifact.direction.title)
                    Text(artifact.reference.kind.rawValue)
                    Text(artifact.reference.format.rawValue)
                    Text(ByteCountFormatter.string(
                        fromByteCount: Int64(clamping: artifact.reference.byteCount),
                        countStyle: .file
                    ))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Text(artifact.reference.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            Spacer()
            if showsOpenIcon {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct ActivityArtifactSelection: Identifiable {
    let id: String
    let activity: Activity
    let artifact: Activity.Artifact

    init(activity: Activity, artifact: Activity.Artifact, index: Int) {
        self.id = "\(activity.id):artifact:\(index)"
        self.activity = activity
        self.artifact = artifact
    }
}

private struct ActivityGroup: Identifiable {
    let id: String
    let activities: [Activity]
    let latestActivity: Activity

    static func makeGroups(from activities: [Activity]) -> [ActivityGroup] {
        let grouped = Dictionary(grouping: activities) { activity in
            activity.operationID.isEmpty ? activity.id : activity.operationID
        }
        return grouped
            .compactMap { ActivityGroup(id: $0.key, activities: $0.value) }
            .sorted { lhs, rhs in
                lhs.latestActivity.occurredAt > rhs.latestActivity.occurredAt
            }
    }

    init?(id: String, activities: [Activity]) {
        let sortedActivities = activities.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt < rhs.occurredAt
            }
            return lhs.id < rhs.id
        }
        guard let latestActivity = sortedActivities.last else {
            return nil
        }
        self.id = id
        self.activities = sortedActivities
        self.latestActivity = latestActivity
    }

    var runID: String? {
        activities.compactMap(\.runID).first
    }

    var title: String {
        if let created = activities.first(where: { $0.kind == "run.created" }),
           !created.summary.isEmpty,
           created.summary != "Run created" {
            return created.summary
        }
        return latestActivity.title
    }

    var summary: String {
        if let terminal = activities.last(where: { $0.kind == "run.finished" }) {
            return terminal.summary
        }
        return latestActivity.summary
    }

    var actorLabel: String {
        let labels = activities.reduce(into: [String]()) { labels, activity in
            let label = "\(activity.actorIdentifier) · \(activity.actorKind.rawValue)"
            if !labels.contains(label) {
                labels.append(label)
            }
        }
        guard let first = labels.first else { return "Unknown actor" }
        guard labels.count > 1 else { return first }
        return "\(first) + \(labels.count - 1) more"
    }

    var timeRange: String {
        guard let first = activities.first, let last = activities.last else { return "" }
        let formatter = Date.FormatStyle.dateTime.hour().minute()
        if Calendar.current.isDate(first.occurredAt, inSameDayAs: last.occurredAt) {
            return "\(first.occurredAt.formatted(formatter)) – \(last.occurredAt.formatted(formatter))"
        }
        return "\(first.occurredAt.formatted(.dateTime.year().month().day().hour().minute())) – \(last.occurredAt.formatted(.dateTime.year().month().day().hour().minute()))"
    }

    var status: Activity.Status {
        let statuses = Set(activities.map(\.status))
        if statuses.contains(.failed) { return .failed }
        if statuses.contains(.blocked) { return .blocked }
        if statuses.contains(.cancelled) { return .cancelled }
        if statuses.contains(.partial) { return .partial }
        if statuses.contains(.running) { return .running }
        if statuses.contains(.succeeded) { return .succeeded }
        return .informational
    }

    var artifactCount: Int {
        activities.reduce(0) { $0 + $1.artifacts.count + $1.omittedArtifactCount }
    }

    var diagnosticCount: Int {
        activities.reduce(0) { $0 + $1.diagnostics.count + $1.omittedDiagnosticCount }
    }
}

private enum ActivityStatusFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case succeeded
    case failed
    case blocked
    case partial
    case cancelled
    case informational

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All outcomes"
        case .running: return "Running"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        case .blocked: return "Blocked"
        case .partial: return "Partial"
        case .cancelled: return "Cancelled"
        case .informational: return "Informational"
        }
    }

    func matches(_ status: Activity.Status) -> Bool {
        self == .all || rawValue == status.rawValue
    }
}

private enum ActivityActorFilter: String, CaseIterable, Identifiable {
    case all
    case agent
    case human
    case cli
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All actors"
        case .agent: return "Agent"
        case .human: return "Human"
        case .cli: return "CLI"
        case .system: return "System"
        }
    }

    func matches(_ actor: Activity.ActorKind) -> Bool {
        self == .all || rawValue == actor.rawValue
    }
}

private enum ActivityKindFilter: String, CaseIterable, Identifiable {
    case all
    case design
    case verification
    case artifact
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All kinds"
        case .design: return "Design changes"
        case .verification: return "Verification"
        case .artifact: return "With artifacts"
        case .progress: return "Progress"
        }
    }

    func matches(_ activity: Activity) -> Bool {
        let kind = activity.kind.lowercased()
        switch self {
        case .all:
            return true
        case .design:
            return activity.sourceKind == .xcircuiteDesignDiff || kind.contains("design")
        case .verification:
            return kind.contains("drc")
                || kind.contains("lvs")
                || kind.contains("verify")
                || kind == "stage.result"
        case .artifact:
            return !activity.artifacts.isEmpty || activity.omittedArtifactCount > 0
        case .progress:
            return kind.hasPrefix("progress.") || kind == "stage.attempt"
        }
    }
}

private extension Activity {
    var isLowSignal: Bool {
        kind.lowercased().hasPrefix("progress.") || kind == "stage.attempt"
    }
}

private extension Activity.Status {
    var title: String {
        rawValue.capitalized
    }

    var systemImage: String {
        switch self {
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
        switch self {
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled, .blocked: return .orange
        case .partial: return .yellow
        case .informational: return .secondary
        }
    }
}

private extension Activity.Artifact {
    var displayName: String {
        let name = URL(filePath: reference.path).lastPathComponent
        return name.isEmpty ? reference.path : name
    }
}

private extension Activity.ArtifactDirection {
    var title: String {
        rawValue.capitalized
    }

    var systemImage: String {
        switch self {
        case .input: return "arrow.down.circle"
        case .output: return "arrow.up.circle"
        case .related: return "link"
        }
    }

    var statusColor: Color {
        switch self {
        case .input: return .blue
        case .output: return .green
        case .related: return .secondary
        }
    }
}
