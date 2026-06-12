import SwiftUI
import CircuitStudioCore

/// Compact property editor presented as a popover when an item is
/// double-clicked on the canvas — edit names and instance parameters
/// without leaving the editing flow.
public struct QuickPropertyEditor: View {
    @Bindable var viewModel: SchematicViewModel
    let targetID: UUID

    /// All edits made while the popover is open form a single undo step.
    @State private var hasRecordedUndo = false

    public init(viewModel: SchematicViewModel, targetID: UUID) {
        self.viewModel = viewModel
        self.targetID = targetID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let index = viewModel.document.components.firstIndex(where: { $0.id == targetID }) {
                componentEditor(index: index)
            } else if let index = viewModel.document.wires.firstIndex(where: { $0.id == targetID }) {
                wireEditor(index: index)
            } else if let index = viewModel.document.labels.firstIndex(where: { $0.id == targetID }) {
                labelEditor(index: index)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func recordUndoOnce() {
        guard !hasRecordedUndo else { return }
        hasRecordedUndo = true
        viewModel.recordForUndo()
    }

    // MARK: - Component

    @ViewBuilder
    private func componentEditor(index: Int) -> some View {
        let component = viewModel.document.components[index]
        let kind = viewModel.catalog.device(for: component.deviceKindID)

        Text(kind?.displayName ?? component.deviceKindID)
            .font(.headline)

        LabeledContent("Name") {
            TextField("Name", text: Binding(
                get: { viewModel.document.components[index].name },
                set: { newValue in
                    recordUndoOnce()
                    viewModel.document.components[index].name = newValue
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 140)
        }

        if let kind {
            let instanceParameters = kind.parameterSchema.filter { !$0.isModelParameter }
            ForEach(instanceParameters) { schema in
                LabeledContent("\(schema.displayName)\(schema.unit.isEmpty ? "" : " (\(schema.unit))")") {
                    TextField(schema.displayName, value: Binding(
                        get: {
                            viewModel.document.components[index].parameters[schema.id]
                                ?? schema.defaultValue ?? 0
                        },
                        set: { newValue in
                            recordUndoOnce()
                            viewModel.document.components[index].parameters[schema.id] = newValue
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                }
            }
        }
    }

    // MARK: - Wire

    @ViewBuilder
    private func wireEditor(index: Int) -> some View {
        Text("Wire")
            .font(.headline)

        LabeledContent("Net Name") {
            TextField("Net Name", text: Binding(
                get: { viewModel.document.wires[index].netName ?? "" },
                set: { newValue in
                    recordUndoOnce()
                    viewModel.document.wires[index].netName = newValue.isEmpty ? nil : newValue
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 140)
        }
    }

    // MARK: - Label

    @ViewBuilder
    private func labelEditor(index: Int) -> some View {
        Text("Net Label")
            .font(.headline)

        LabeledContent("Name") {
            TextField("Name", text: Binding(
                get: { viewModel.document.labels[index].name },
                set: { newValue in
                    recordUndoOnce()
                    viewModel.document.labels[index].name = newValue
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 140)
        }
    }
}

#Preview("Component") {
    let vm = SchematicPreview.selectedComponentViewModel()
    return QuickPropertyEditor(
        viewModel: vm,
        targetID: vm.document.components.first?.id ?? UUID()
    )
}
