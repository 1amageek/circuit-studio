import SwiftUI

/// Single tab descriptor used by `PaneTabBar`. Lifted out of the bar so call sites
/// can declare static `[PaneTabItem<X>]` without spelling the bar's other generic params.
struct PaneTabItem<Tab: Hashable>: Identifiable {
    let id: Tab
    let systemImage: String
    let help: String

    init(_ id: Tab, systemImage: String, help: String) {
        self.id = id
        self.systemImage = systemImage
        self.help = help
    }
}

/// Reusable Xcode-style tab bar for the navigator, inspector, and debug area panes.
///
/// Each tab is a borderless icon button. The selected tab is tinted with the accent color
/// and the bar is backed by a thin material with a single trailing divider.
struct PaneTabBar<Tab: Hashable, Trailing: View>: View {
    @Binding var selection: Tab
    let items: [PaneTabItem<Tab>]
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                tabButton(item)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func tabButton(_ item: PaneTabItem<Tab>) -> some View {
        let isActive = selection == item.id
        return Button {
            selection = item.id
        } label: {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .regular))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(item.help)
    }
}

extension PaneTabBar where Trailing == EmptyView {
    init(selection: Binding<Tab>, items: [PaneTabItem<Tab>]) {
        self._selection = selection
        self.items = items
        self.trailing = { EmptyView() }
    }
}

/// Compact header used inside a tab content area to label the pane.
/// Shows a small title flush left, with optional trailing accessory.
struct PaneSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
