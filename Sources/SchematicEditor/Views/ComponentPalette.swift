import SwiftUI
import CircuitStudioCore

/// Palette for selecting components to place on the schematic.
/// Reads from DeviceCatalog grouped by category — no hardcoded device types.
public struct ComponentPalette: View {
    @Bindable var viewModel: SchematicViewModel

    public init(viewModel: SchematicViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(DeviceCategory.allCases, id: \.self) { category in
                let devices = viewModel.catalog.devices(in: category)
                if !devices.isEmpty {
                    Text(categoryDisplayName(category))
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(devices) { kind in
                        Button {
                            viewModel.tool = .place(kind.id)
                        } label: {
                            HStack {
                                Image(systemName: kind.symbol.iconName)
                                    .frame(width: 20)
                                Text(kind.displayName)
                                Spacer()
                                if isActivePlacement(kind.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            Text("Tools")
                .font(.headline)
                .padding(.horizontal)

            Button {
                viewModel.tool = .select
            } label: {
                toolRow(icon: "arrow.uturn.left", name: "Select", active: isSelectTool)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.tool = .wire
            } label: {
                toolRow(icon: "line.diagonal", name: "Wire", active: isWireTool)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.tool = .label
            } label: {
                toolRow(icon: "tag", name: "Net Label", active: isLabelTool)
            }
            .buttonStyle(.plain)
        }
    }

    private func toolRow(icon: String, name: String, active: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
            Text(name)
            Spacer()
            if active {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var isSelectTool: Bool {
        if case .select = viewModel.tool { return true }
        return false
    }

    private var isWireTool: Bool {
        if case .wire = viewModel.tool { return true }
        return false
    }

    private var isLabelTool: Bool {
        if case .label = viewModel.tool { return true }
        return false
    }

    private func isActivePlacement(_ deviceKindID: String) -> Bool {
        if case .place(let id) = viewModel.tool, id == deviceKindID {
            return true
        }
        return false
    }

    private func categoryDisplayName(_ category: DeviceCategory) -> String {
        switch category {
        case .passive: return "Passive"
        case .source: return "Sources"
        case .semiconductor: return "Semiconductor"
        case .controlled: return "Controlled Sources"
        case .special: return "Special"
        }
    }
}

#Preview("Component Palette") {
    ComponentPalette(viewModel: SchematicPreview.emptyViewModel())
        .frame(width: 220)
        .padding()
}

#Preview("Palette — Resistor Selected") {
    let vm = SchematicPreview.emptyViewModel()
    vm.tool = .place("resistor")
    return ComponentPalette(viewModel: vm)
        .frame(width: 220)
        .padding()
}
