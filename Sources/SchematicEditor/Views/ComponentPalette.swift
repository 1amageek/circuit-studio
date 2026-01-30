import SwiftUI
import CircuitStudioCore

/// Keynote-style component palette with category tabs and a grid of device symbols.
/// Displayed inside a popover triggered from the schematic canvas overlay.
public struct ComponentPalette: View {
    @Bindable var viewModel: SchematicViewModel
    @State private var selectedCategory: DeviceCategory = .passive
    let onSelect: () -> Void

    public init(viewModel: SchematicViewModel, onSelect: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onSelect = onSelect
    }

    private var devices: [DeviceKind] {
        viewModel.catalog.devices(in: selectedCategory)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 72, maximum: 90), spacing: 8)
    ]

    public var body: some View {
        VStack(spacing: 0) {
            categoryTabs
            Divider()
            deviceGrid
        }
        .frame(width: 280)
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        HStack(spacing: 2) {
            ForEach(DeviceCategory.allCases, id: \.self) { category in
                let count = viewModel.catalog.devices(in: category).count
                if count > 0 {
                    Button {
                        selectedCategory = category
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: categoryIcon(category))
                                .font(.body)
                            Text(categoryShortName(category))
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            selectedCategory == category
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .foregroundStyle(selectedCategory == category ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Device Grid

    private var deviceGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(devices) { kind in
                    DeviceGridCell(
                        kind: kind,
                        isActive: isActivePlacement(kind.id)
                    ) {
                        viewModel.tool = .place(kind.id)
                        onSelect()
                    }
                }
            }
            .padding(10)
        }
        .frame(minHeight: 120, maxHeight: 300)
    }

    // MARK: - Helpers

    private func isActivePlacement(_ deviceKindID: String) -> Bool {
        if case .place(let id) = viewModel.tool, id == deviceKindID {
            return true
        }
        return false
    }

    private func categoryIcon(_ category: DeviceCategory) -> String {
        switch category {
        case .passive: return "rectangle"
        case .source: return "bolt.circle"
        case .semiconductor: return "memorychip"
        case .controlled: return "diamond"
        case .special: return "minus"
        }
    }

    private func categoryShortName(_ category: DeviceCategory) -> String {
        switch category {
        case .passive: return "Passive"
        case .source: return "Sources"
        case .semiconductor: return "Semi"
        case .controlled: return "Ctrl"
        case .special: return "Special"
        }
    }
}

// MARK: - Device Grid Cell

/// A single grid cell showing the device circuit symbol and name.
private struct DeviceGridCell: View {
    let kind: DeviceKind
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                SymbolThumbnail(kind: kind)
                    .frame(width: 48, height: 48)

                Text(kind.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                isActive
                    ? Color.accentColor.opacity(0.12)
                    : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isActive ? Color.accentColor : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Symbol Thumbnail

/// Renders a device's circuit symbol as a small thumbnail using Canvas.
private struct SymbolThumbnail: View {
    let kind: DeviceKind

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            // Scale the symbol to fit within the thumbnail
            let symbolSize = kind.symbol.size
            let padding: CGFloat = 6
            let available = CGSize(
                width: size.width - padding * 2,
                height: size.height - padding * 2
            )
            let scaleX = available.width / max(symbolSize.width, 1)
            let scaleY = available.height / max(symbolSize.height, 1)
            let scale = min(scaleX, scaleY, 1.2)

            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: scale, y: scale)

            renderShape(kind.symbol.shape, in: &context)

            context.scaleBy(x: 1 / scale, y: 1 / scale)
            context.translateBy(x: -center.x, y: -center.y)
        }
    }

    private func renderShape(
        _ shape: SymbolShape,
        in context: inout GraphicsContext
    ) {
        let strokeColor: Color = .primary
        let lineWidth: CGFloat = 1.2

        switch shape {
        case .custom(let commands):
            for command in commands {
                renderCommand(command, in: &context, strokeColor: strokeColor, lineWidth: lineWidth)
            }
        case .ic(let width, let height):
            let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            context.stroke(Path(rect), with: .color(strokeColor), lineWidth: lineWidth)
        }
    }

    private func renderCommand(
        _ command: DrawCommand,
        in context: inout GraphicsContext,
        strokeColor: Color,
        lineWidth: CGFloat
    ) {
        switch command {
        case .line(let from, let to):
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        case .rect(let origin, let size):
            let rect = CGRect(origin: origin, size: size)
            context.stroke(Path(rect), with: .color(strokeColor), lineWidth: lineWidth)

        case .circle(let center, let radius):
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.stroke(Path(ellipseIn: rect), with: .color(strokeColor), lineWidth: lineWidth)

        case .arc(let center, let radius, let startAngle, let endAngle):
            var path = Path()
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .radians(startAngle),
                endAngle: .radians(endAngle),
                clockwise: false
            )
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        case .text(let string, let at, let fontSize):
            let text = Text(string).font(.system(size: fontSize))
            context.draw(context.resolve(text), at: at, anchor: .center)
        }
    }
}

// MARK: - Previews

#Preview("Component Palette") {
    ComponentPalette(viewModel: SchematicPreview.emptyViewModel())
        .padding()
}

#Preview("Palette — Semiconductor") {
    let vm = SchematicPreview.emptyViewModel()
    return ComponentPalette(viewModel: vm)
        .padding()
}
