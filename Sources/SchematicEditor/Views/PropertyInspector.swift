import SwiftUI
import CircuitStudioCore

/// Inspector panel for editing component properties.
/// Generates parameter editors from DeviceKind.parameterSchema — no hardcoded device types.
public struct PropertyInspector: View {
    @Bindable var viewModel: SchematicViewModel

    public init(viewModel: SchematicViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if let selectedID = viewModel.document.selection.first,
               let index = viewModel.document.components.firstIndex(where: { $0.id == selectedID }) {
                componentInspector(index: index)
            } else if let selectedID = viewModel.document.selection.first,
                      let index = viewModel.document.wires.firstIndex(where: { $0.id == selectedID }) {
                wireInspector(index: index)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "cursorarrow.click.2",
                    description: Text("Select a component to edit its properties")
                )
            }
        }
    }

    @ViewBuilder
    private func componentInspector(index: Int) -> some View {
        let component = viewModel.document.components[index]
        let kind = viewModel.catalog.device(for: component.deviceKindID)

        Form {
            Section("Component") {
                LabeledContent("Type", value: kind?.displayName ?? component.deviceKindID)
                TextField("Name", text: Binding(
                    get: { viewModel.document.components[index].name },
                    set: { viewModel.document.components[index].name = $0 }
                ))
            }

            Section("Position") {
                HStack {
                    Text("X")
                    TextField("X", value: Binding<Double>(
                        get: { Double(viewModel.document.components[index].position.x) },
                        set: { viewModel.document.components[index].position.x = CGFloat($0) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Y")
                    TextField("Y", value: Binding<Double>(
                        get: { Double(viewModel.document.components[index].position.y) },
                        set: { viewModel.document.components[index].position.y = CGFloat($0) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Rotation")
                    TextField("Degrees", value: Binding<Double>(
                        get: { viewModel.document.components[index].rotation },
                        set: { viewModel.document.components[index].rotation = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    Text("\u{00B0}")
                }
                Toggle("Mirror X", isOn: Binding(
                    get: { viewModel.document.components[index].mirrorX },
                    set: { newValue in
                        viewModel.recordForUndo()
                        viewModel.document.components[index].mirrorX = newValue
                        viewModel.updateConnectedWires(forComponentAt: index)
                    }
                ))
                Toggle("Mirror Y", isOn: Binding(
                    get: { viewModel.document.components[index].mirrorY },
                    set: { newValue in
                        viewModel.recordForUndo()
                        viewModel.document.components[index].mirrorY = newValue
                        viewModel.updateConnectedWires(forComponentAt: index)
                    }
                ))
            }

            Section("Parameters") {
                parameterEditor(index: index, kind: kind)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func parameterEditor(index: Int, kind: DeviceKind?) -> some View {
        if let kind, !kind.parameterSchema.isEmpty {
            ForEach(kind.parameterSchema) { schema in
                HStack {
                    Text("\(schema.displayName) (\(schema.unit))")
                    Spacer()
                    TextField(schema.displayName, value: Binding(
                        get: {
                            viewModel.document.components[index].parameters[schema.id]
                                ?? schema.defaultValue ?? 0
                        },
                        set: { newValue in
                            viewModel.document.components[index].parameters[schema.id] = newValue
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                }
            }
        } else {
            Text("No parameters")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func wireInspector(index: Int) -> some View {
        Form {
            Section("Wire") {
                TextField("Net Name", text: Binding(
                    get: { viewModel.document.wires[index].netName ?? "" },
                    set: { viewModel.document.wires[index].netName = $0.isEmpty ? nil : $0 }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Component Selected") {
    PropertyInspector(viewModel: SchematicPreview.selectedComponentViewModel())
        .frame(width: 300)
}

#Preview("Wire Selected") {
    PropertyInspector(viewModel: SchematicPreview.selectedWireViewModel())
        .frame(width: 300)
}

#Preview("No Selection") {
    PropertyInspector(viewModel: SchematicPreview.emptyViewModel())
        .frame(width: 300, height: 200)
}
