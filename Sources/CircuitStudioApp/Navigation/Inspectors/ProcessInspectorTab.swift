import SwiftUI
import AppKit
import CircuitStudioCore

/// Process / technology configuration: foundry, corner, temperature override, model file.
struct ProcessInspectorTab: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            if let technology = appState.processConfiguration.technology {
                technologySection(technology)
                cornerSection(technology)
                overrideSection
                actionsSection
            } else {
                emptySection
            }
        }
        .formStyle(.grouped)
    }

    private func technologySection(_ technology: ProcessTechnology) -> some View {
        Section("Technology") {
            LabeledContent("Name", value: technology.name)
            if let version = technology.version, !version.isEmpty {
                LabeledContent("Version", value: version)
            }
            if let foundry = technology.foundry, !foundry.isEmpty {
                LabeledContent("Foundry", value: foundry)
            }
        }
    }

    @ViewBuilder
    private func cornerSection(_ technology: ProcessTechnology) -> some View {
        if !technology.cornerSet.corners.isEmpty {
            Section("Corner") {
                Picker("Corner", selection: Binding<UUID?>(
                    get: { appState.processConfiguration.cornerID },
                    set: { appState.processConfiguration.cornerID = $0 }
                )) {
                    Text("Default").tag(UUID?.none)
                    ForEach(technology.cornerSet.corners) { corner in
                        Text(corner.name).tag(Optional(corner.id))
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var overrideSection: some View {
        Section("Override") {
            TextField("Temperature (°C)", text: temperatureOverrideBinding)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var actionsSection: some View {
        Section {
            HStack {
                Button("Change…") { openProcessFile() }
                Button("Clear", role: .destructive) { clearProcess() }
                Spacer()
            }
        }
    }

    private var emptySection: some View {
        Section("Process") {
            Text("No process loaded")
                .foregroundStyle(.secondary)
            Button("Load Process…") { openProcessFile() }
        }
    }

    // MARK: - Bindings & actions

    private var temperatureOverrideBinding: Binding<String> {
        Binding(
            get: {
                if let value = appState.processConfiguration.temperatureOverride {
                    return String(format: "%.4g", value)
                }
                return ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    appState.processConfiguration.temperatureOverride = nil
                    return
                }
                if let parsed = Double(trimmed) {
                    appState.processConfiguration.temperatureOverride = parsed
                }
            }
        )
    }

    private func openProcessFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "json")!,
            .plainText,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let technology = try JSONDecoder().decode(ProcessTechnology.self, from: data)
                appState.processConfiguration.technology = technology
                appState.processConfiguration.cornerID = technology.defaultCornerID
                appState.processConfiguration.resolveIncludes = true
                appState.log("Loaded process: \(technology.name)", kind: .success)
            } catch {
                appState.simulationError = "Failed to load process: \(error.localizedDescription)"
            }
        }
    }

    private func clearProcess() {
        appState.processConfiguration = ProcessConfiguration()
    }
}
